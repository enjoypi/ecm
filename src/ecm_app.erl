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

start(_StartType, _StartArgs) ->
  {ok, NodeType} = application:get_env(gconfig, node_type),
  {ok, Pid} = ecm_sup:start_link(NodeType),
  ok = ecm:start(),
  {ok, Pid}.

stop(_State) ->
  ok.



