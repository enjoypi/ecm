%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(scale_helper).

-include_lib("common_test/include/ct.hrl").
%% API
-export([
  end_per_suite/1,
  init_per_suite/1,
  hatch_test/1,
  server_test/1
]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
init_per_suite(Config) ->
  {ok, NodeType} = application:get_env(ecm, node_type),
  ct:pal("nodes\t~p", [nodes()]),
  ct:pal("mnesia:system_info\t~p", [mnesia:system_info(all)]),
  [{type, NodeType} | Config].

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
end_per_suite(Config) ->
  Type = ?config(type, Config),
  ct:pal("~p processes\t~p\ttotal processes\t~p", [
    Type,
    ecm_db:size(Type),
    length(processes())
  ]).

%%--------------------------------------------------------------------
%% @doc Test case function. (The name of it must be specified in
%%              the all/0 list or in a test case group for the test case
%%              to be executed).
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%% Comment = term()
%%   A comment about the test case that will be printed in the html log.
%%
%% @spec TestCase(Config0) ->
%%           ok | exit() | {skip,Reason} | {comment,Comment} |
%%           {save_config,Config1} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
hatch_test(_Config) ->
  ok.

%%--------------------------------------------------------------------
%% @doc Test case function. (The name of it must be specified in
%%              the all/0 list or in a test case group for the test case
%%              to be executed).
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%% Comment = term()
%%   A comment about the test case that will be printed in the html log.
%%
%% @spec TestCase(Config0) ->
%%           ok | exit() | {skip,Reason} | {comment,Comment} |
%%           {save_config,Config1} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
server_test(Config) ->
  Type = ?config(type, Config),
  Id = random_id(),

  RefMsg = make_ref(),
  {ok, Pid} = ecm:hatch(Type, Id, ecm_test_sup, start_child, [Id], {self(), RefMsg}),
  receive
    RefMsg ->
      ok
  after 10000 ->
    exit(timeout)
  end,

  %% test call
  CallMsg = make_ref(),
  {ok, Pid, CallMsg} = ecm:call(Type, Id, CallMsg),

  %% test cast
  CastRef = make_ref(),
  {ok, Pid} = ecm:cast(Type, Id, {self(), CastRef}),
  receive
    CastRef ->
      ok
  after 10000 ->
    exit(timeout)
  end,

  %% test info
  InfoRef = make_ref(),
  {ok, Pid} = ecm:send(Type, Id, {self(), InfoRef}),
  receive
    InfoRef ->
      ok
  after 10000 ->
    exit(timeout)
  end,
  ok.
%%%===================================================================
%%% Internal functions
%%%===================================================================
random_id() ->
  crypto:rand_uniform(1001, 9223372036854775807).
