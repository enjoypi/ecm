%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%% Created : 16. 十二月 2016 上午11:06
%%%-------------------------------------------------------------------
-module(ecm_check).

-behaviour(gen_server).

%% API
-export([
  start_link/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3]).

-record(state, {}).

start_link() ->
  gameserver_app:reload(),
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start_checktimer() ->
  {ok, _TRef} = timer:send_after(60000, self(), {check}),
  ok.

init([]) ->
  ok = start_checktimer(),
  {ok, #state{}}.

handle_call(_Request, _From, State) ->
  {reply, unmatched, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info({check}, State) ->
  Mem = erlang:memory(),
  {_, Proused} = lists:keyfind(processes_used, 1, Mem),
  mnesia:dirty_write({ecm_nodeinfo, node(), Proused, misc:now()}),
  ok = start_checktimer(),
  {noreply, State};

handle_info({'EXIT', _, _}, State) ->
  {noreply, State};
handle_info(_, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

