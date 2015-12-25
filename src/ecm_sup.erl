%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(ecm_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(NodeType) ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, [NodeType]).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart intensity, and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([NodeType]) ->

  RestartStrategy = one_for_one,
  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,

  SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

  init_sup(SupFlags, NodeType).

%%%===================================================================
%%% Internal functions
%%%===================================================================
init_sup(SupFlags, master) ->
  MasterSup = {
    ecm_master_sup,
    {ecm_master_sup, start_link, []},
    permanent,
    5000,
    supervisor,
    [ecm_master_sup]
  },
  init_test_sup(SupFlags, [MasterSup], application:get_env(ecm, test_sup));
init_sup(SupFlags, _) ->
  OtherSup = {
    ecm_other_sup,
    {ecm_other_sup, start_link, []},
    permanent,
    5000,
    supervisor,
    [ecm_other_sup]
  },
  init_test_sup(SupFlags, [OtherSup], application:get_env(ecm, test_sup)).

init_test_sup(SupFlags, Children, undefined) ->
  {ok, {SupFlags, Children}};
init_test_sup(SupFlags, Children, {ok, TestSupName}) ->
  TestSup = {
    TestSupName,
    {TestSupName, start_link, []},
    permanent,
    5000,
    supervisor,
    [TestSupName]
  },
  {ok, {SupFlags, lists:append(Children, [TestSup])}}.
