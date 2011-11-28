%% -------------------------------------------------------------------
%%
%% bdberl: DB API Tests
%%
%% @copyright 2008-9 The Hive http://www.thehive.com/
%% @author Dave "dizzyd" Smith <dizzyd@dizzyd.com>
%% @author Phil Toland <phil.toland@gmail.com>
%% @author Jon Meredith <jon@jonmeredith.com>
%% @end
%%
%% @copyright 2011 Basho Technologies http://www.basho.com/
%% @author Greg Burd <greg@basho.com>
%% @end
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%%
%% -------------------------------------------------------------------
-module(bdberl_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

all() ->
    [open_should_create_database_if_none_exists,
     open_should_allow_opening_multiple_databases,
     close_should_fail_with_invalid_db_handle,
     get_should_fail_when_getting_a_nonexistant_record,
     get_should_return_a_value_when_getting_a_valid_record,
     put_should_succeed_with_manual_transaction,
     put_should_rollback_with_failed_manual_transaction,
%     del_should_remove_a_value, %TODO: why is this disabled
     transaction_should_commit_on_success,
     transaction_should_abort_on_exception,
     transaction_should_abort_on_user_abort,
     transaction_error_should_return_error,
     update_should_save_value_if_successful,
     update_should_accept_args_for_fun,
     port_should_return_transaction_timeouts,
     cursor_should_iterate, cursor_get_should_pos, cursor_should_fail_if_not_open,
     put_commit_should_end_txn,
     data_dir_should_be_priv_dir,
     delete_should_remove_file,
     delete_should_fail_if_db_inuse,
     truncate_should_empty_database,
     truncate_all_should_empty_all_databases,
     btree_stat_should_report_on_success,
     hash_stat_should_report_on_success,
     stat_should_fail_on_bad_dbref,
     lock_stat_should_report_on_success,
     log_stat_should_report_on_success,
     memp_stat_should_report_on_success,
     mutex_stat_should_report_on_success,
     txn_stat_should_report_on_success,
     data_dirs_info_should_report_on_success,
     lg_dir_info_should_report_on_success,
     start_after_stop_should_be_safe].



dbconfig(Config) ->
    Cfg = [
           {set_data_dir, ?config(priv_dir, Config)},
           {set_flags, 'DB_TXN_NOSYNC'},
           {log_set_config, 'DB_LOG_IN_MEMORY'}
          ],
    list_to_binary(lists:flatten([io_lib:format("~s ~s\n", [K,V]) || {K, V} <- Cfg])).


init_per_suite(Config) ->
    DbHome = ?config(priv_dir, Config),
    os:putenv("DB_HOME", DbHome),
    ok = file:write_file(DbHome ++ "DB_CONFIG", dbconfig(Config)),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(TestCase, Config) ->
    ct:print("~p", [TestCase]),
    {ok, Db} = bdberl:open("api_test.db", btree, [create, exclusive]),
    [{db, Db}|Config].

end_per_testcase(_TestCase, Config) ->
    ok = bdberl:close(?config(db, Config)),
    ok = bdberl:delete_database("api_test.db").

open_should_create_database_if_none_exists(Config) ->
    DbName = filename:join([?config(priv_dir, Config), "api_test.db"]),
    true = filelib:is_file(DbName).

open_should_allow_opening_multiple_databases(_Config) ->
    %% Open up another db -- should use dbref 1 as that's the first available
    {ok, 1} = bdberl:open("api_test2.db", btree).

close_should_fail_with_invalid_db_handle(_Config) ->
    {error, invalid_db} = bdberl:close(21000).

get_should_fail_when_getting_a_nonexistant_record(Config) ->
    not_found = bdberl:get(?config(db, Config), bad_key).

get_should_return_a_value_when_getting_a_valid_record(Config) ->
    Db = ?config(db, Config),
    ok = bdberl:put(Db, mykey, avalue),
    {ok, avalue} = bdberl:get(Db, mykey).

put_should_succeed_with_manual_transaction(Config) ->
    Db = ?config(db, Config),
    ok = bdberl:txn_begin(),
    ok = bdberl:put(Db, mykey, avalue),
    ok = bdberl:txn_commit(),
    {ok, avalue} = bdberl:get(Db, mykey).

put_should_rollback_with_failed_manual_transaction(Config) ->
    Db = ?config(db, Config),
    ok = bdberl:txn_begin(),
    ok = bdberl:put(Db, mykey, avalue),
    ok = bdberl:txn_abort(),
    not_found = bdberl:get(Db, mykey).

del_should_remove_a_value(Config) ->
    Db = ?config(db, Config),
    ok = bdberl:put(Db, mykey, avalue),
    {ok, avalue} = bdberl:get(Db, mykey),
    ok = bdberl:del(Db, mykey),
    not_found = bdberl:get(Db, mykey).

transaction_should_commit_on_success(Config) ->
    Db = ?config(db, Config),
    F = fun() -> bdberl:put(Db, mykey, avalue) end,
    {ok, ok} = bdberl:transaction(F),
    {ok, avalue} = bdberl:get(Db, mykey).

transaction_should_abort_on_exception(Config) ->
    Db = ?config(db, Config),

    F = fun() ->
            bdberl:put(Db, mykey, should_not_see_this),
            throw(testing)
        end,

    {error, {transaction_failed, testing}} = bdberl:transaction(F),
    not_found = bdberl:get(Db, mykey).

transaction_should_abort_on_user_abort(Config) ->
    Db = ?config(db, Config),

    F = fun() ->
            bdberl:put(Db, mykey, should_not_see_this),
            abort
        end,

    {error, transaction_aborted} = bdberl:transaction(F),
    not_found = bdberl:get(Db, mykey).

transaction_error_should_return_error(_Config) ->
    Db = ?config(db, _Config),
    F = fun() ->
                bdberl:put(Db, mykey, should_not_see_this),
                %% Explicitly kill the transaction so that when transaction/2
                %% tries to commit it will fail
                bdberl:txn_abort(),
                %% Value to return
                avalue
        end,
    %% This should fail as there is no transaction to commit
    {error,no_txn} = bdberl:transaction(F).

update_should_save_value_if_successful(Config) ->
    Db = ?config(db, Config),
    ok = bdberl:put(Db, mykey, avalue),

    F = fun(Key, Value) ->
            mykey = Key,
            avalue = Value,
            newvalue
        end,

    {ok, newvalue} = bdberl:update(Db, mykey, F),
    {ok, newvalue} = bdberl:get(Db, mykey).

update_should_accept_args_for_fun(Config) ->
    Db = ?config(db, Config),
    ok = bdberl:put(Db, mykey, avalue),

    F = fun(_Key, _Value, Args) ->
            look_at_me = Args, % This is all we are interested in
            newvalue
        end,

    {ok, newvalue} = bdberl:update(Db, mykey, F, look_at_me).

port_should_return_transaction_timeouts(_Config) ->
    %% Test transaction timeouts
    {ok, 500000} = bdberl:get_txn_timeout().

cursor_should_iterate(Config) ->
    Db = ?config(db, Config),

    %% Store some sample values in the db
    ok = bdberl:put(Db, key1, value1),
    ok = bdberl:put(Db, key2, value2),
    ok = bdberl:put(Db, key3, value3),

    %% Validate that the cursor returns each value in order (ASSUME btree db)
    ok = bdberl:cursor_open(Db),
    {ok, key1, value1} = bdberl:cursor_next(),
    {ok, key2, value2} = bdberl:cursor_next(),
    {ok, key3, value3} = bdberl:cursor_next(),
    not_found = bdberl:cursor_next(),

    %% Validate that the current key is key3
    {ok, key3, value3} = bdberl:cursor_current(),

    %% Now move backwards (should jump to key2, since we are "on" key3)
    {ok, key2, value2} = bdberl:cursor_prev(),
    {ok, key1, value1} = bdberl:cursor_prev(),
    not_found = bdberl:cursor_prev(),

    ok = bdberl:cursor_close().

cursor_get_should_pos(Config) ->
    Db = ?config(db, Config),

    %% Store some sample values in the db
    ok = bdberl:put(Db, key1, value1),
    ok = bdberl:put(Db, key2, value2),
    ok = bdberl:put(Db, key3, value3),
    ok = bdberl:put(Db, key4, value4),

    %% Validate that the cursor is positioned properly, then
    %% returns the next value.
    ok = bdberl:cursor_open(Db),
    {ok, value2} = bdberl:cursor_get(key2),
    {ok, key3, value3} = bdberl:cursor_next(),
    {ok, value2} = bdberl:cursor_get(key2),
    {ok, key3, value3} = bdberl:cursor_next(),
    {ok, value1} = bdberl:cursor_get(key1),
    {ok, key2, value2} = bdberl:cursor_next(),
    {ok, key3, value3} = bdberl:cursor_next(),
    {ok, key4, value4} = bdberl:cursor_next(),
    not_found = bdberl:cursor_next(),

    ok = bdberl:cursor_close().

cursor_should_fail_if_not_open(_Config) ->
    {error, no_cursor} = bdberl:cursor_next(),
    {error, no_cursor} = bdberl:cursor_prev(),
    {error, no_cursor} = bdberl:cursor_current(),
    {error, no_cursor} = bdberl:cursor_get(),
    {error, no_cursor} = bdberl:cursor_close().

put_commit_should_end_txn(Config) ->
    Db = ?config(db, Config),

    %% Start a transaction
    ok = bdberl:txn_begin(),
    ok = bdberl:put_commit(Db, key1, value1),

    %% Commit should now fail since the txn is done
    {error, no_txn} = bdberl:txn_commit(),

    %% Verify data got committed
    {ok, value1} = bdberl:get(Db, key1).

data_dir_should_be_priv_dir(Config) ->
    PrivDir = ?config(priv_dir, Config),
    [PrivDir] = bdberl:get_data_dirs().

delete_should_remove_file(Config) ->
    {ok, Db} = bdberl:open("mytest.bdb", btree),
    ok = bdberl:close(Db),

    Fname = filename:join([?config(priv_dir, Config), "mytest.bdb"]),
    true = filelib:is_file(Fname),

    ok = bdberl:delete_database("mytest.bdb"),

    false = filelib:is_file(Fname).

delete_should_fail_if_db_inuse(Config) ->
    Fname = filename:join([?config(priv_dir, Config), "api_test.db"]),
    true = filelib:is_file(Fname),
    {error, _} = bdberl:delete_database(Fname),
    true = filelib:is_file(Fname).

truncate_should_empty_database(Config) ->
    Db = ?config(db, Config),
    ok = bdberl:put(Db, mykey, avalue),
    ok = bdberl:truncate(Db),
    not_found = bdberl:get(Db, mykey).

truncate_all_should_empty_all_databases(Config) ->
    Db = ?config(db, Config),
    ok = bdberl:put(Db, mykey, avalue),
    ok = bdberl:truncate(),
    not_found = bdberl:get(Db, mykey).

btree_stat_should_report_on_success(_Config) ->
    {ok, Db} = bdberl:open("btree_stat.bdb", btree),
    {ok, Stat} = bdberl:stat(Db, []),
    %% Check stats are zero on the new db
    0 = proplists:get_value(nkeys, Stat),
    0 = proplists:get_value(ndata, Stat),

    %%  Put a record and check the number of records updates
    ok = bdberl:put(Db, mykey, avalue),

    {ok, Stat1} = bdberl:stat(Db, []),
    %% Check stats are zero on the new db
    1 = proplists:get_value(nkeys, Stat1),
    1 = proplists:get_value(ndata, Stat1),
    done.


hash_stat_should_report_on_success(_Config) ->
    {ok, Db} = bdberl:open("hash_stat.bdb", hash),
    {ok, Stat} = bdberl:stat(Db, []),
    %% Check stats are zero on the new db
    0 = proplists:get_value(nkeys, Stat),
    0 = proplists:get_value(ndata, Stat),

    %%  Put a record and check the number of records updates
    ok = bdberl:put(Db, mykey, avalue),

    {ok, Stat1} = bdberl:stat(Db, []),
    %% Check stats are zero on the new db
    1 = proplists:get_value(nkeys, Stat1),
    1 = proplists:get_value(ndata, Stat1),
    done.

stat_should_fail_on_bad_dbref(_Config) ->
    {error, invalid_db} = bdberl:stat(10000000, []),
    done.

lock_stat_should_report_on_success(_Config) ->
    {ok, Stat} = bdberl:lock_stat([]),
    %% Check a lock stat that that probably won't change
    2147483647 = proplists:get_value(cur_maxid, Stat),
    done.

log_stat_should_report_on_success(_Config) ->
    {ok, Stat} = bdberl:log_stat([]),
    %% Check a log stat that that probably won't change
    264584 = proplists:get_value(magic, Stat),
    done.

memp_stat_should_report_on_success(_Config) ->
    {ok, Gstat, Fstat} = bdberl:memp_stat([]),
    true = is_list(Fstat),
    true = is_list(Gstat),
    done.

mutex_stat_should_report_on_success(_Config) ->
    {ok, _Stat} = bdberl:mutex_stat([]),
    done.

txn_stat_should_report_on_success(_Config) ->
    {ok, _GStat1, []} = bdberl:txn_stat([]),
    bdberl:txn_begin(),
    {ok, _GStat2, [_ATxnStat]} = bdberl:txn_stat([]),
    bdberl:txn_abort(),
    {ok, _GStat3, []} = bdberl:txn_stat([]),
    done.

data_dirs_info_should_report_on_success(_Config) ->
    {ok, _DataDirs} = bdberl:get_data_dirs_info().

lg_dir_info_should_report_on_success(_Config) ->
    {ok, _LgDir, _Fsid, _MBytesAvail} = bdberl:get_lg_dir_info().

%% Check the bdberl_logger gets reinstalled after stopping
start_after_stop_should_be_safe(_Config) ->

    %% Make sure bdberl_logger is running by using bdberl
    Self = self(),
    F = fun() ->
                bdberl:log_stat(),
                Self ! ok
        end,
    spawn(F),
    receive
        ok ->
            ok
    end,
    true = lists:keymember(bdberl_logger, 1, supervisor:which_children(kernel_safe_sup)),

    %% Make sure bdberl_logger is really removed on stop
    bdberl:stop(),
    false = lists:keymember(bdberl_logger, 1, supervisor:which_children(kernel_safe_sup)),

    %% A bdb operation to open the port and get it re-registered
    spawn(F),
    receive
        ok ->
            ok
    end,
    true = lists:keymember(bdberl_logger, 1, supervisor:which_children(kernel_safe_sup)),
    ok.


