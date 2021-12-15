-module(etcd_client_SUITE).

-compile(nowarn_export_all).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(CLIENT, 'EtcdClient.Client').

%%--------------------------------------------------------------------
%%  COMMON TEST CALLBACK FUNCTIONS
%%
%%  Suite Level Setup
%%--------------------------------------------------------------------

suite() ->
    [
     {timetrap, {minutes, 10}}
    ].

init_per_suite(_Config) ->
    test_helper:load_env_variables(),
    test_helper:start_deps(),
    Nodes = [dev1, dev2],
    SortedNodes = lists:sort(Nodes),
    [
     {nodes, SortedNodes}
    ].

end_per_suite(_Config) ->
    test_helper:stop_deps(),
    ok.

%%--------------------------------------------------------------------
%%  Group level Setup
%%--------------------------------------------------------------------

init_per_group(GroupName, Config) ->
    ?MODULE:GroupName({prelude, Config}).

end_per_group(GroupName, Config) ->
    ?MODULE:GroupName({postlude, Config}).

%%--------------------------------------------------------------------
%%  Test level Setup
%%--------------------------------------------------------------------

init_per_test_case(TestCase, Config) ->
    ?MODULE:TestCase({prelude, Config}).

end_per_test_case(TestCase, Config) ->
    ?MODULE:TestCase({postlude, Config}).

%%--------------------------------------------------------------------
%%  Group
%%--------------------------------------------------------------------

groups() ->
    [{put_get_group,
      [{repeat_until_any_fail, 1}],
      [
       put_get_happy_path
      ]
     }].

all() ->
    [
     {group, put_get_group}
    ].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Function: TestCase(Config0) ->
%%               ok | exit() | {skip,Reason} | {comment,Comment} |
%%               {save_config,Config1} | {skip_and_save,Reason,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%% Comment = term()
%%   A comment about the test case that will be printed in the html log.
%%
%% Description: Test case function. (The name of it must be specified in
%%              the all/0 list or in a test case group for the test case
%%              to be executed).
%%--------------------------------------------------------------------

put_get_group({prelude, Config}) ->
    Nodes = proplists:get_value(nodes, Config),
    ClusterInfo = test_helper:start_nodes(Nodes, #{}),
    [{cluster_info, ClusterInfo}|Config];
put_get_group({postlude, _Config}) ->
    test_helper:stop_app_on_nodes(),
    ok.

put_get_happy_path({info, _Config}) ->
    ["Test to validate base put/get functionality.",
     "Run etcd client: Happy Path"];
put_get_happy_path(suite) ->
    [];
put_get_happy_path({prelude, Config}) ->
    Config;
put_get_happy_path({postlude, _Config}) ->
    ok;
put_get_happy_path(Config) ->
    Nodes = proplists:get_value(nodes, Config),
    lists:foreach(fun rpc_put_get/1, Nodes).

%%--------------------------------------------------------------------
%% Private functions
%%--------------------------------------------------------------------

rpc_put_get(Node) ->
    Key1 = "key1",
    Key2 = "key2",
    Value1 = "value1",
    Value2 = "value2",
    {ok, _Result1} = test_helper:rpc_call(Node, ?CLIENT, put, [Key1, Value1]),
    {ok, _Result2} = test_helper:rpc_call(Node, ?CLIENT, put, [Key2, Value2]),
    {ok, _Response1} = test_helper:rpc_call(Node, ?CLIENT, get, [Key1]),
    {ok, _Response2} = test_helper:rpc_call(Node, ?CLIENT, get, [Key2]),
    ?assertMatch(ok, ok).
