%% -------------------------------------------------------------------
%%
%% bdberl: Port Driver Stress tests
%% Copyright (c) 2008 The Hive.  All rights reserved.
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
-module(stress_SUITE).
-compile(export_all).
-include_lib("common_test/include/ct.hrl").

%% NOTE: all of the tests are set for a low number of iterations to guarantee
%% that they all pass and run in a reasonable amount of time. That kinda defeats
%% the purpose of the test, tho. Work is ongoing to make this a useful test suite.

all() ->
    [rewrite_array_test,
     rewrite_bytes_test,
     write_array_test,
     write_bytes_test].

dbconfig(Config) ->
    Cfg = [
           {set_data_dir, ?config(priv_dir, Config)},
           {set_flags, 'DB_TXN_WRITE_NOSYNC'},
           {set_cachesize, '0 536870912 1'},
           {set_lg_max, '1048576000'},
           {set_lg_bsize, '5368709120'},
           {set_log_config, 'DB_LOG_IN_MEMORY'}
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
    Size = 1024 * 1024,
    Chunk = crypto:rand_bytes(Size),
    Name = io_lib:format("~p.db", [TestCase]),
    {ok, Db} = bdberl:open(Name, hash),
    [{size, Size}, {chunk, Chunk}, {db, Db}|Config].

end_per_testcase(_TestCase, Config) ->
    bdberl:close(?config(db, Config)),
    ok.

%%---------------------------------------------------------------------------

rewrite_array_test(Config) ->
    %% If you try to run this one for more than 2K iterations than the Erlang
    %% VM will die with a memory allocation error when creating the binary.
    ct:print("Running rewrite_array test for 2000 iterations..."),
    Chunk = ?config(chunk, Config),
    rewrite_array(?config(db, Config), Chunk, [Chunk], 20).

rewrite_array(_Db, _Block, _Bytes, 0) ->
    ok;
rewrite_array(Db, Block, Bytes, Iter) ->
    bdberl:put(Db, 1, Bytes),
    rewrite_array(Db, Block, [Block|Bytes], Iter - 1).

%%---------------------------------------------------------------------------

rewrite_bytes_test(Config) ->
    ct:print("Running rewrite_bytes test for 2500 iterations..."),
    rewrite_bytes(?config(db, Config), ?config(chunk, Config), 25).

rewrite_bytes(_Db, _Bytes, 0) ->
    ok;
rewrite_bytes(Db, Bytes, Iter) ->
    bdberl:put(Db, 1, Bytes),
    rewrite_bytes(Db, Bytes, Iter - 1).

%%---------------------------------------------------------------------------

write_array_test(Config) ->
    ct:print("Running write_array test for 150 iterations..."),
    Chunk = ?config(chunk, Config),
    write_array(?config(db, Config), Chunk, [Chunk], 15).

write_array(_Db, _Block, _Bytes, 0) ->
    ok;
write_array(Db, Block, Bytes, Iter) ->
    bdberl:put(Db, Iter, Bytes),
    write_array(Db, Block, [Block|Bytes], Iter - 1).

%%---------------------------------------------------------------------------

write_bytes_test(Config) ->
    ct:print("Running write_bytes test for 2500 iterations..."),
    write_bytes(?config(db, Config), ?config(chunk, Config), 25).

write_bytes(_Db, _Bytes, 0) ->
    ok;
write_bytes(Db, Bytes, Iter) ->
    bdberl:put(Db, Iter, Bytes),
    write_bytes(Db, Bytes, Iter - 1).
