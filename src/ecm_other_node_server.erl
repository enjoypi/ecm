%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(ecm_other_node_server).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(ROUTINE, 5000).

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  timer:send_interval(?ROUTINE, routine),
  {ok, #state{}}.

handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

handle_cast({master,Master}, State) ->
  monitor_node(Master, true),
  {noreply, State};
handle_cast(_Msg, State) ->
  {noreply, State}.

% 与master节点失联
handle_info({nodedown, Node}, State) ->
  elog:warn(system, "Master [~p] down, try to connect...", [Node]),
  {ok, Masters0} = application:get_env(gconfig, masters),
  Masters = ecm:connect_to_master(Masters0),
  case  length(Masters)> 0 of
    true ->
      elog:warn(system, "reconnect master successed: ~p", [Masters]),
      ok;
    false ->
      {ok, NodeType} = application:get_env(gconfig, node_type),
      elog:warn(system, "none of master can be connected!. gs ~p shutdown", [NodeType]),
      LostMaster = application:get_env(ecm, lost_master),
      case LostMaster of
        {ok, halt} ->
          %% supervisord will not restart this node if exit code is 0
          erlang:halt(0, [{flush, false}]);
        _Other ->
          application:stop(gameserver)
      end
  end,
  {noreply, State};
% 本节点状态统计&上传
handle_info(routine, State) ->
  {noreply, State};

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

