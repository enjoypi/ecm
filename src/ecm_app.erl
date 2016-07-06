%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(ecm_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @spec start(StartType, StartArgs) -> {ok, Pid} |
%%                                      {ok, Pid, State} |
%%                                      {error, Reason}
%%      StartType = normal | {takeover, Node} | {failover, Node}
%%      StartArgs = term()
%% @end
%%--------------------------------------------------------------------
start(_StartType, _StartArgs) ->
  {ok, NodeType} = application:get_env(ecm, node_type),
  {ok, Pid} = ecm_sup:start_link(NodeType),
  {ok, Masters} = application:get_env(ecm, masters),
  true = connect_master(Masters),
  ok = ecm_db:start(NodeType, Masters),
  {ok, Pid}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @spec stop(State) -> void()
%% @end
%%--------------------------------------------------------------------
stop(_State) ->
  ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
connect_master([]) ->
  false;
connect_master(Masters) when is_list(Masters) ->
  connect_master(true, Masters).

connect_master(_, []) ->
  true;
connect_master(true, [OneMaster | Others]) ->
  connect_master(net_kernel:connect_node(OneMaster), Others).
