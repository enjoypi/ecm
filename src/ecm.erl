%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(ecm).

%% API
-export([
  all_nodes/0,
  async_hatch/5,
  async_hatch/6,
  async_hatch/7,
  call/3,
  cast/3,
  current_node/1,
  finish_start/0,
  get/2,
  hatch/5,
  hatch/6,
  hatch/7,
  multi_cast/2,
  nodes/1,
  processes/1,
  send/3,
  set/4,
  size/1,
  sync_table/1,
  sync_table/2,
  wait_dependencies/1
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
  hatch(ecm_db:get(Type, Id), Type, Id, M, F, A, Msg, Selector).

async_hatch(Type, Id, M, F, A) ->
  async_hatch(Type, Id, M, F, A, undefined).

async_hatch(Type, Id, M, F, A, Msg) ->
  async_hatch(Type, Id, M, F, A, Msg, fun random_node/1).

async_hatch(Type, Id, M, F, A, Msg, Selector) ->
  Fun =
    fun() ->
      hatch(ecm_db:get(Type, Id), Type, Id, M, F, A, Msg, Selector)
    end,
  spawn(Fun),
  ok.

multi_cast(Type, Msg) ->
  ok = ecm_db:foreach_pid(Type,
    fun(Pid) ->
      gen_server:cast(Pid, Msg)
    end).

nodes(Type) ->
  ecm_db:nodes(Type).

processes(Type) ->
  ecm_db:processes(Type).

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

hatch(undefined, Type, Id, M, F, A, Msg, Selector) ->
  {ok, Node} = Selector(Type),
  NodeString = atom_to_list(Node),
  [Flag, _Host] = string:tokens(NodeString, "@"),
  Table = ecm_db:table_name(Type),
  Fun =
    fun() ->
      case ecm_db:read(Table, Id, write) of
        [{_, Id, Pid, _}] ->
          {ok, Pid};
        _ ->
          {ok, Pid} =
            case rpc:call(Node, M, F, A) of
              {ok, P} ->
                {ok, P};
              {ok, P, _Info} ->
                {ok, P};
              Error ->
                Error
            end,
          ecm_db:write({Table, Id, Pid, Node}),
          ecm_db:write({ecm_processes, Pid, Table, Id, Flag}),
          ecm_process_server:monitor(Pid),
          {ok, Pid}
      end
    end,
  case ecm_db:transaction(Fun) of
    {atomic, {ok, Pid}} ->
      cast({ok, Pid}, Msg);
    Reason ->
      {error, Reason}
  end;
hatch({ok, Pid}, _Type, _Id, _M, _F, _A, Msg, _Selector) ->
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
  choose_node(Nodes);
random_node(Type) ->
  random_node(ecm_db:nodes(Type)).

choose_node(Nodes) ->
  try sort_nodes(Nodes) of
    {ok, Node} -> {ok, Node}
  catch
    _:_ ->
      Index = rand:uniform(length(Nodes)),
      Node = lists:nth(Index, Nodes),
      {ok, Node}
  end.

sort_nodes(Nodes) ->
  NodeTable = lists:foldl(
    fun(Node, Res) ->
      [Memory | _] = mnesia:dirty_read({ecm_nodeinfo, Node}),
      {_, _, Process_Used, UpLoad_Time} = Memory,
      Now_Time = misc:now(),
      Dis_Time = Now_Time - UpLoad_Time,
      if
        Dis_Time < 120000 -> [{Node, Process_Used} | Res];
        true -> Res
      end
    end, [], Nodes),
  OrderNodeTab =
    lists:sort(
    fun(A, B) ->
      {_, Numa} = A,
      {_, Numb} = B,
      Numa < Numb
    end, NodeTable),
  {Node, _} = lists:nth(1, OrderNodeTab),
  {ok, Node}.

default_dependent(master) ->
  [];
default_dependent(_) ->
  [master].

wait_dependencies(Type) ->
  Dependent = application:get_env(ecm, dependent, []),
  DependentTimeout = application:get_env(ecm, dependent_timeout, 60),
  ok = wait_dependencies(lists:append(default_dependent(Type), Dependent), 0, DependentTimeout).

wait_dependencies(_, Times, Times) ->
  timeout;
wait_dependencies([], _Times, _MaxTimes) ->
  ok;
wait_dependencies(Dependent = [Type | Others], Times, MaxTimes) ->
  case ecm_db:nodes(Type) of
    {Type, Nodes} when is_list(Nodes), length(Nodes) > 0 ->
      wait_dependencies(Others, Times, MaxTimes);
    _ ->
      receive after 1000 -> ok end,
      wait_dependencies(Dependent, Times + 1, MaxTimes)
  end.