/* -------------------------------------------------------------------
 *
 * bdberl: Thread Pool
 * Copyright (c) 2008-9 The Hive http://www.thehive.com/
 * Authors: Dave "dizzyd" Smith <dizzyd@dizzyd.com>
 *          Phil Toland <phil.toland@gmail.com>
 *          Jon Meredith <jon@jonmeredith.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * ------------------------------------------------------------------- */

#include <db.h>
#include "bdberl_drv.h"
#include "bdberl_tpool.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>

static void* bdberl_tpool_main(void* tpool);
static TPoolJob* next_job(TPool* tpool);
static int remove_pending_job(TPool* tpool, TPoolJob* job);
static void cleanup_job(TPool* tpool, TPoolJob* job);
static int is_active_job(TPool* tpool, TPoolJob* job);

#define LOCK(tpool) erl_drv_mutex_lock(tpool->lock)
#define UNLOCK(tpool) erl_drv_mutex_unlock(tpool->lock)


TPool* bdberl_tpool_start(unsigned int thread_count)
{
    TPool* tpool = driver_alloc(sizeof(TPool));
    memset(tpool, '\0', sizeof(TPool));

    // Initialize lock, cv, etc.
    tpool->lock         = erl_drv_mutex_create("bdberl_tpool_lock");
    tpool->work_cv      = erl_drv_cond_create("bdberl_tpool_work_cv");
    tpool->cancel_cv    = erl_drv_cond_create("bdberl_tpool_cancel_cv");
    tpool->threads      = driver_alloc(sizeof(ErlDrvTid) * thread_count);
    tpool->thread_count = thread_count;

    // Startup all the threads
    int i;
    for (i = 0; i < thread_count; i++)
    {
        int rc = erl_drv_thread_create("bdberl_tpool_thread", &(tpool->threads[i]), &bdberl_tpool_main, (void*)tpool, 0);
        if (0 != rc) {
            // TODO: Figure out good way to deal with errors in this situation (should be rare, but still...)
            fprintf(stderr, "Failed to spawn an erlang thread for the BDB thread pools! %s\n", erl_errno_id(rc));
            fflush(stderr);
        }
    }
    return tpool;
}

void bdberl_tpool_stop(TPool* tpool)
{
    LOCK(tpool);

    // Set the shutdown flag and broadcast a notification
    tpool->shutdown = 1;
    erl_drv_cond_broadcast(tpool->work_cv);

    // Clean out the queue of pending jobs -- invoke their cleanup function

    // Wait for until active_threads hits zero
    while (tpool->active_threads > 0)
    {
        erl_drv_cond_wait(tpool->work_cv, tpool->lock);
    }

    // Join up with all the workers
    int i = 0;
    for (i = 0; i < tpool->thread_count; i++)
    {
        erl_drv_thread_join(tpool->threads[i], 0);
    }

    // Cleanup
    erl_drv_cond_destroy(tpool->work_cv);
    erl_drv_cond_destroy(tpool->cancel_cv);
    driver_free(tpool->threads);
    UNLOCK(tpool);
    erl_drv_mutex_destroy(tpool->lock);
    driver_free(tpool);
}

void bdberl_tpool_run(TPool* tpool, TPoolJobFunc main_fn, void* arg, TPoolJobFunc cancel_fn,
                      TPoolJob** job_ptr)
{
    // Allocate and fill a new job structure
    TPoolJob* job = *job_ptr = driver_alloc(sizeof(TPoolJob));
    memset(job, '\0', sizeof(TPoolJob));
    job->main_fn = main_fn;
    job->arg = arg;
    job->cancel_fn = cancel_fn;

    // Sync up with the tpool and add the job to the pending queue
    LOCK(tpool);

    if (tpool->pending_jobs)
    {
        // Make sure the current last job points to this one next
        tpool->last_pending_job->next = job;
    }
    else
    {
        // No pending jobs; this is the first
        tpool->pending_jobs = job;
    }

    tpool->last_pending_job = job;
    tpool->pending_job_count++;

    // Generate a notification that there is work todo.
    // TODO: I think this may not be necessary, in the case where there are already other
    // pending jobs. Not sure ATM, however, so will be on safe side
    erl_drv_cond_broadcast(tpool->work_cv);
    UNLOCK(tpool);
}

void bdberl_tpool_cancel(TPool* tpool, TPoolJob* job)
{
    LOCK(tpool);

    // Remove the job from the pending queue
    if (remove_pending_job(tpool, job))
    {
        // Job was removed from pending -- unlock and notify the job that it got canceled
        UNLOCK(tpool);

        if (job->cancel_fn)
        {
            (*(job->cancel_fn))(job->arg);
        }

        // Delete the job structure
        driver_free(job);
        return;
    }

    // Job not in the pending queue -- check the active queue.
    if (is_active_job(tpool, job))
    {
        // Job is currently active -- mark it as cancelled (so we get notified) and wait for it
        job->canceled = 1;
        while (job->running)
        {
            erl_drv_cond_wait(tpool->cancel_cv, tpool->lock);
        }

        // Job is no longer running and should now be considered dead. Cleanup is handled by
        // the worker.
        UNLOCK(tpool);
        return;
    }

    // Job was neither active nor pending -- it must have gotten run/cleaned up while we
    // were waiting on the thread pool lock. Regardless, it's now done/gone and the cancel
    // is a success.
    UNLOCK(tpool);
}

static void* bdberl_tpool_main(void* arg)
{
    TPool* tpool = (TPool*)arg;

    LOCK(tpool);

    tpool->active_threads++;

    while(1)
    {
        // Check for shutdown...
        if (tpool->shutdown)
        {
            tpool->active_threads--;
            erl_drv_cond_broadcast(tpool->work_cv);
            UNLOCK(tpool);
            return 0;
        }

        // Get the next job
        TPoolJob* job = next_job(tpool);
        if (job)
        {
            // Unlock to avoid blocking others
            UNLOCK(tpool);

            // Invoke the function
            (*(job->main_fn))(job->arg);

            // Relock
            LOCK(tpool);

            // Mark the job as not running (important for cancellation to know it's done)
            job->running = 0;

            // If the job was cancelled, signal the cancellation cv so that anyone waiting on the
            // job knows it's complete
            if (job->canceled)
            {
                erl_drv_cond_broadcast(tpool->cancel_cv);
            }

            // Cleanup the job (remove from active list, free, etc.)
            cleanup_job(tpool, job);
        }
        else
        {
            // Wait for a job to come available then jump back to top of loop
            erl_drv_cond_wait(tpool->work_cv, tpool->lock);
        }
    }

    return 0;
}

static TPoolJob* next_job(TPool* tpool)
{
    if (tpool->pending_jobs)
    {
        // Pop the job off the queue
        TPoolJob* job = tpool->pending_jobs;
        tpool->pending_jobs = job->next;

        // No more pending jobs; update last job pointer
        if (!tpool->pending_jobs)
        {
            tpool->last_pending_job = 0;
        }


        // Mark the job as running and add to the active list
        job->running = 1;
        if (tpool->active_jobs)
        {
            job->next = tpool->active_jobs;
        }
        else
        {
            job->next = NULL;
        }
        tpool->active_jobs = job;

        // Update counters
        tpool->pending_job_count--;
        tpool->active_job_count++;

        return job;
    }
    return 0;
}

static int remove_pending_job(TPool* tpool, TPoolJob* job)
{
    TPoolJob* current = tpool->pending_jobs;
    TPoolJob* last = 0;
    while (current)
    {
        if (current == job)
        {
            // Found our match -- look back and connect the last item to our next. Also,
            // make sure that last_pending_job is updated accordingly
            if (last)
            {
                last->next = current->next;
            }
            else
            {
                tpool->pending_jobs = current->next;
            }

            // If this job was the last one, make sure that we update the last_pending_job
            // pointer to reference the _previous_ node
            if (tpool->last_pending_job == job)
            {
                tpool->last_pending_job = last;
            }

            tpool->pending_job_count--;
            return 1;
        }

        // Next...
        last = current;
        current = current->next;
    }

    return 0;
}

static void cleanup_job(TPool* tpool, TPoolJob* job)
{
    // Loop over active jobs and remove the job from that list
    TPoolJob* current = tpool->active_jobs;
    TPoolJob* last = 0;
    while (current)
    {
        if (current == job)
        {
            // Found our match -- look back and connect the last item to our next
            if (last)
            {
                last->next = current->next;
            }
            else
            {
                tpool->active_jobs = current->next;
            }

            break;
        }

        // Move to next item
        last = current;
        current = current->next;
    }

    // Update counter and free the job structure
    tpool->active_job_count--;
    driver_free(job);
}

static int is_active_job(TPool* tpool, TPoolJob* job)
{
    TPoolJob* current = tpool->active_jobs;
    while (current)
    {
        if (current == job)
        {
            return 1;
        }

        current = current->next;
    }
    return 0;
}

// Return the number of pending and active jobs
void bdberl_tpool_job_count(TPool* tpool, unsigned int *pending_count_ptr,
                             unsigned int *active_count_ptr)
{
    LOCK(tpool);
    *pending_count_ptr = tpool->pending_job_count;
    *active_count_ptr = tpool->active_job_count;
    UNLOCK(tpool);
}

// Returns a unique identifier pair for the current thread of control
void bdberl_tpool_thread_id(DB_ENV *env, pid_t *pid, db_threadid_t *tid)
{
    if (pid)
        *pid = getpid();
    if (tid)
      *tid = (db_threadid_t)pthread_self();
}

char *bdberl_tpool_thread_id_string(DB_ENV *dbenv, pid_t pid, db_threadid_t tid, char *buf)
{
    snprintf(buf, DB_THREADID_STRLEN, "[pid:%08X/tid:%08X]", (unsigned int)pid, (unsigned int)tid);
    return buf;
}

// Returns non-zero if the thread of control, identified by the pid and tid arguments,
// is still running.
// If DB_MUTEX_PROCESS_ONLY is set in flags then return only if the process (pid) is
// alive, ignore the thread ID.
int bdberl_tpool_thread_is_alive(DB_ENV *dbenv, pid_t pid, db_threadid_t tid, u_int32_t flags)
{
    static char path[200];
    static struct stat sb;
    int alive = 0;

    snprintf(path, 200, "/dev/%d/status", pid);
    if (stat(path, &sb))
    {
        if (flags & DB_MUTEX_PROCESS_ONLY)
            alive = 1;
        else
            if (pthread_kill(tid, 0) != ESRCH)
              alive = 1;
    }
    DBG("bdberl_tpool_thread_is_alive(%08X, %08X, %d) = %d\n", pid, tid, flags, alive);
    return alive;
}
