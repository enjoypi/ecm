%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(ecm_master_node_server).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(WATCH_INTERVAL, 60000).

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
  {ok, #state{}, 0}.

handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

handle_cast({nodeup, Node}, State) ->
  % elog:info(system, "Node up: ~p.", [Node]),
  monitor_node(Node, true),
  {noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(watch, State) ->
  Types = mnesia:dirty_all_keys(ecm_nodes),
  lists:map(fun watch/1, Types),
  erlang:send_after(?WATCH_INTERVAL, self(), watch),
  {noreply, State};

handle_info({nodedown, Node}, State) ->
  % elog:info(system, "Node down ~p.", [Node]),
  ecm:delete_node(Node),
  {noreply, State};

handle_info(timeout, State) ->
  erlang:send_after(?WATCH_INTERVAL, self(), watch),
  {noreply, State};

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

watch(Type) ->
  elog:debug(ecm, "~p\t~p", [Type, ecm:table_size(Type)]).
