%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(ecm).

%% API
-export([
  all_nodes/0,
  call/3,
  cast/3,
  current_node/1,
  finish_start/0,
  get/2,
  hatch/5,
  hatch/6,
  hatch/7,
  hatch_child/5,
  hatch_child/6,
  hatch_child/7,
  multi_cast/2,
  nodes/1,
  send/3,
  set/4,
  size/1,
  sync_table/1,
  sync_table/2
]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
all_nodes() ->
  ecm_db:all_nodes().

call(Type, Id, Msg) ->
  call(ecm_db:get(Type, Id), Msg).

-spec cast(Type :: atom(), Id :: term(), Msg :: term()) -> {ok, pid()} | undefined.
cast(Type, Id, Msg) ->
  cast(ecm_db:get(Type, Id), Msg).

current_node(_Type) ->
  {ok, node()}.

finish_start() ->
  {ok, NodeType} = application:get_env(ecm, node_type),
  ecm_db:finish_start(NodeType).

get(Type, Id) ->
  ecm_db:get(Type, Id).

hatch(Type, Id, M, F, A) ->
  hatch(Type, Id, M, F, A, undefined).

hatch(Type, Id, M, F, A, Msg) ->
  hatch(Type, Id, M, F, A, Msg, fun random_node/1).

hatch(Type, Id, M, F, A, Msg, Selector) ->
  hatch(Type, Id, M, F, A, Msg, Selector, []).

hatch(Type, Id, M, F, A, Msg, Selector, Options) ->
  hatch(ecm_db:get(Type, Id), Type, Id, M, F, A, Msg, Selector, Options).

hatch_child(Type, Id, M, F, A) ->
  hatch_child(Type, Id, M, F, A, undefined).

hatch_child(Type, Id, M, F, A, Msg) ->
  hatch_child(Type, Id, M, F, A, Msg, fun random_node/1).

hatch_child(Type, Id, M, F, A, Msg, Selector) ->
  Fun =
    fun() ->
      hatch_child(ecm_db:get(Type, Id), Type, Id, M, F, A, Msg, Selector)
    end,
  global:trans({{Type, Id}, self()}, Fun).

multi_cast(Type, Msg) ->
  ok = ecm_db:foreach_pid(Type,
    fun(Pid) ->
      gen_server:cast(Pid, Msg)
    end).

nodes(Type) ->
  ecm_db:nodes(Type).

send(Type, Id, Msg) ->
  send(ecm_db:get(Type, Id), Msg).

set(Type, Id, Node, Pid) ->
  ecm_db:set(Type, Id, Node, Pid).

size(Type) ->
  ecm_db:size(Type).

sync_table(Type) ->
  ecm_db:sync_table(Type).

sync_table(Table, TabDef) ->
  ecm_db:sync_table(Table, TabDef).

%%%===================================================================
%%% Internal functions
%%%===================================================================

call({ok, Pid}, Msg) when Msg =/= undefined ->
  {ok, Pid, gen_server:call(Pid, Msg)};
call(_, _) ->
  undefined.

cast({ok, Pid}, undefined) ->
  {ok, Pid};
cast({ok, Pid}, Msg) ->
  ok = gen_server:cast(Pid, Msg),
  {ok, Pid};
cast(_, _) ->
  undefined.

hatch(undefined, Type, Id, M, F, A, Msg, Selector, Options) ->
  {ok, Node} = Selector(Type),
  Pid = spawn_opt(Node, M, F, A, Options),
  ok = ecm_db:set(Type, Id, Node, Pid),
  send({ok, Pid}, Msg);
hatch({ok, _Pid}, _Type, _Id, _M, _F, _A, _Msg, _Selector, _Options) ->
  already_exists.

hatch_child(undefined, Type, Id, M, F, A, Msg, Selector) ->
  {ok, Node} = Selector(Type),
  %% startchild_ret() = {ok, Child :: child()}
  %%             | {ok, Child :: child(), Info :: term()}
  %%             | {error, startchild_err()}
  {ok, Pid} =
    case rpc:call(Node, M, F, A) of
      {ok, P} ->
        {ok, P};
      {ok, P, _Info} ->
        {ok, P};
      Error ->
        Error
    end,
  ok = ecm_db:set(Type, Id, Node, Pid),
  cast({ok, Pid}, Msg);
hatch_child({ok, Pid}, _Type, _Id, _M, _F, _A, Msg, _Selector) ->
  cast({ok, Pid}, Msg).

send({ok, Pid}, undefined) ->
  {ok, Pid};
send({ok, Pid}, Msg) ->
  Msg = erlang:send(Pid, Msg),
  {ok, Pid};
send(_, _) ->
  undefined.

random_node([]) ->
  undefined;
random_node({_Type, Nodes}) when is_list(Nodes) ->
  Index = rand:uniform(length(Nodes)),
  Node = lists:nth(Index, Nodes),
  {ok, Node};
random_node(Type) ->
  random_node(ecm_db:nodes(Type)).
