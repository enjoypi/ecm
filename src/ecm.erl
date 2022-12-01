%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(ecm).

%% API
-export([
  all_nodes/0,
  all_nodes/1,
  all_processes/1,
  set_process/4,
  set_process/5,
  get_process/2,
  del_process/3,
  call/3,
  cast/3,
  get_process_list/1,
  get_process_list/2,

  async_hatch/5,
  async_hatch/6,
  async_hatch/7,
  current_node/1,
  connect_to_master/1,
  start/0,
  finish_start/0,
  delete_node/1,
  hatch/5,
  hatch/6,
  hatch/7,
  multi_cast/2,
  send/3,
  table_size/1,
  wait_dependencies/1,
  idle_node/1
]).

%% ecm_Type
-record(ecm_process, {id, pid, node, share}).

%% tables for masters
-record(ecm_nodes, {type, node}).

%%nodes memory info
-record(ecm_nodeinfo, {node, memory, time}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
all_nodes() ->
  Types = mnesia:dirty_all_keys(ecm_nodes),
  lists:map(fun all_nodes/1, Types).

call(Type, Id, Msg) ->
  call(get_process(Type, Id), Msg).

-spec cast(Type :: atom(), Id :: term(), Msg :: term()) -> {ok, pid()} | undefined.
cast(Type, Id, Msg) ->
  cast(get_process(Type, Id), Msg).

current_node(_Type) ->
  {ok, node()}.

start() ->
  {ok, NodeType} = application:get_env(gconfig, node_type),
  {ok, Masters} = application:get_env(gconfig, masters),
  ok = application:ensure_started(mnesia),
  true = (length(connect_to_master(Masters)) > 0),
  {ok, _} = mnesia:change_config(extra_db_nodes, Masters),
  ok = mnesia:wait_for_tables([schema], 60000),
  ok = sync_table(NodeType),
  ets:new(ecm_table_names, [set, {read_concurrency, true}, named_table, public]),
  ok.

% 连接到Master 返回可用的Master列表
connect_to_master([]) -> [];
connect_to_master(Masters) when is_list(Masters) ->
  connect_to_master([], Masters).

connect_to_master(Acc, []) -> Acc;
connect_to_master(Acc, [Node | Others]) ->
  case {Node == node(), net_kernel:connect_node(Node)} of
    {true, _} -> connect_to_master([Node | Acc], Others);
    {false, true} ->
      gen_server:cast({ecm_master_node_server, Node}, {nodeup, node()}),
      gen_server:cast(ecm_other_node_server, {master, Node}),
      connect_to_master([Node | Acc], Others);
    _ -> connect_to_master(Acc, Others)
  end.


finish_start() ->
  {ok, NodeType} = application:get_env(gconfig, node_type),
  ok = mnesia:wait_for_tables([ecm_nodes], 60000),
  ok = sync_other_tables(),
  {atomic, _} = mnesia:transaction(
    fun() ->
      ok = mnesia:write(#ecm_nodes{type = NodeType, node = node()})
    end),
  ok.

del_process(Type, Id, Pid) when is_pid(Pid) ->
  Table = table_name(Type),
  case catch mnesia:dirty_read(Table, Id) of
    %% must match Pid
    [{_, _, Pid, _, _} | _] ->
      ok = mnesia:dirty_delete(Table, Id);
    _ ->
      ok
  end.

% 删除节点上所有的服务
delete_node([], _) -> ok;
delete_node([NodeType | L], Node) ->
  ok = mnesia:dirty_delete_object({ecm_nodes, NodeType, Node}),
  TableName = table_name(NodeType),
  Record = {TableName, '$1', '_', Node, '_'},
  case lists:member(TableName, mnesia:system_info(tables)) of
    false -> ignore;
    true ->
      case catch mnesia:dirty_select(TableName, [{Record, [], ['$1']}]) of
        [] -> ignore;
        Ids when is_list(Ids) ->
          [mnesia:dirty_delete(TableName, Id) || Id <- Ids];
        {'EXIT', _Reason} ->
          ignore
      end
  end,
  delete_node(L, Node).

delete_node(Node) ->
  elog:warn(system, "delete node: ~p", [Node]),
  NodeRecord = #ecm_nodes{type = '$1', node = Node},
  List = mnesia:dirty_select(ecm_nodes, [{NodeRecord, [], ['$1']}]),
  delete_node(List, Node).

get_process_list(Type) ->
  get_process_list(Type, undefined).

get_process_list(Type, Where) ->
  Processes = all_processes(Type),
  Results = lists:foldl(
    fun({_, _, Pid, Node, _}, Acc) ->
      case Where of
        undefined ->
          [Pid | Acc];
        Node ->
          [Pid | Acc];
        _ ->
          Acc
      end
    end,
    [],
    Processes
  ),
  Results.

try_get_process(Type, Id, Time) when Type =/= undefined, is_atom(Type), Id =/= undefined, Time > 0 ->
  Table = table_name(Type),
  case catch mnesia:dirty_read(Table, Id) of
    [{_, _, Pid, _, _} | _] ->
      {ok, Pid};
    [] ->
      undefined;
    Exception ->
      elog:error(system, "get process failed, Type=~p, Id=~p, exception: ~p", [Type, Id, Exception]),
      timer:sleep(300),
      try_get_process(Type, Id, Time - 1)
  end;
try_get_process(_, _, _) ->
  error.

get_process(Type, Id) ->
  try_get_process(Type, Id, 5).


hatch(Type, Id, M, F, A) ->
  hatch(Type, Id, M, F, A, undefined).

hatch(Type, Id, M, F, A, Msg) ->
  hatch(Type, Id, M, F, A, Msg, fun idle_node/1).

hatch(Type, Id, M, F, A, Msg, Selector) ->
  Fun =
    fun() ->
      hatch(get_process(Type, Id), Type, Id, M, F, A, Msg, Selector)
    end,
  {Type, Nodes} = all_nodes(Type),
  global:trans({{Type, Id}, self()}, Fun, Nodes).

async_hatch(Type, Id, M, F, A) ->
  async_hatch(Type, Id, M, F, A, undefined).

async_hatch(Type, Id, M, F, A, Msg) ->
  async_hatch(Type, Id, M, F, A, Msg, fun random_node/1).

async_hatch(Type, Id, M, F, A, Msg, Selector) ->
  Fun =
    fun() ->
      hatch(get_process(Type, Id), Type, Id, M, F, A, Msg, Selector)
    end,
  spawn(Fun),
  ok.

multi_cast(Type, Msg) ->
  ok = foreach_pid(Type,
    fun(Pid) ->
      gen_server:cast(Pid, Msg)
    end).

all_processes(Type) ->
  mnesia:dirty_select(table_name(Type), [{{'_', '_', '_', '_', '_'}, [], ['$_']}]).

send(Type, Id, Msg) ->
  send(get_process(Type, Id), Msg).

set_process(Type, Id, Node, Pid) ->
  set_process(Type, Id, Node, Pid, #{}).
set_process(Type, Id, Node, Pid, Share) ->
  Table = table_name(Type),
  Result =
    case catch mnesia:dirty_read(Table, Id) of
      [{Table, Id, OPid, ONode, _}] ->
        {ok, {Id, OPid, ONode, Pid, Node}};
      _ ->
        ok
    end,
  ok = mnesia:dirty_write({Table, Id, Pid, Node, Share}),
  Result.

table_size(Type) ->
  ets:info(table_name(Type), size).

sync_table(master) ->
  {ok, Masters} = application:get_env(gconfig, masters),
  NodesTabDef = [
    {attributes, record_info(fields, ecm_nodes)},
    {ram_copies, Masters},
    {type, bag}
  ],
  ok = sync_table(ecm_nodes, NodesTabDef),
  NodeInfoTabDef = [
    {attributes, record_info(fields, ecm_nodeinfo)},
    {ram_copies, Masters},
    {type, set}
  ],
  ok = sync_table(ecm_nodeinfo, NodeInfoTabDef);
sync_table(Type) ->
  %% can create atom
  Table = list_to_atom(lists:concat(["ecm_", Type])),
  Nodes = [node() | nodes()],
  TabDef = [
    {attributes, record_info(fields, ecm_process)},
    {ram_copies, Nodes},
    {type, set}
  ],
  ok = sync_table(Table, TabDef),
  Mem = erlang:memory(),
  {_, Total} = lists:keyfind(total, 1, Mem),
  mnesia:dirty_write({ecm_nodeinfo, node(), Total, misc:now()}),
  ecm_check:start_link(),
  ok.

sync_table(Table, TabDef) ->
  on_add_table_copy(mnesia:add_table_copy(Table, node(), ram_copies), Table, TabDef).

all_nodes(Type) ->
  Records =
    case catch mnesia:dirty_read(ecm_nodes, Type) of
      R when is_list(R) ->
        R;
      _ ->
        []
    end,
  {Type, [Node || {ecm_nodes, _Type, Node} <- Records]}.

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

hatch(error, Type, Id, _M, _F, A, Msg, _Selector) ->
  elog:error(system, "hatch failed, Type=~p, Id=~p, Arg=~p, Msg=~p", [Type, Id, A, Msg]),
  {error, hatch_failed};
hatch(undefined, Type, Id, M, F, A, Msg, Selector) ->
  {ok, Node} = Selector(Type),
  Table = table_name(Type),
  Fun =
    fun() ->
      case mnesia:read(Table, Id, write) of
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
          {ok, Pid}
      end
    end,
  case mnesia:transaction(Fun) of
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

idle_node([]) ->
  undefined;
idle_node({Type, Nodes}) when is_list(Nodes) ->
  choose_idle_node(Type, Nodes);
idle_node(Type) ->
  idle_node(all_nodes(Type)).

choose_idle_node(Type, Nodes) ->
  % 选择一个 lua_server 数量最少的节点
  Fun =
    fun(Node, Acc) ->
      ProcessCnt = length(get_process_list(Type, Node)),
      [{Node, ProcessCnt} | Acc]
    end,

  NodeProcessCnt = lists:foldl(Fun, [], Nodes),
  NodeProcessCnt1 = lists:sort(
    fun({_, Cnt1}, {_, Cnt2}) -> Cnt1 < Cnt2 end,
    NodeProcessCnt
  ),

  [{_, MinCnt} | _] = NodeProcessCnt1,
  NodeProcessCnt2 = lists:foldl(fun(Elem = {_, Cnt}, Acc) ->
    DiffCnt = Cnt - MinCnt,
    case DiffCnt =< 1 of
      true ->
        [Elem | Acc];
      _ ->
        Acc
    end
  end, [], NodeProcessCnt1),
  RandIndex = rand:uniform(length(NodeProcessCnt2)),
  {ChooseNode, _} = lists:nth(RandIndex, NodeProcessCnt2),
  {ok, ChooseNode}.

random_node([]) ->
  undefined;
random_node({_Type, Nodes}) when is_list(Nodes) ->
  choose_node(Nodes);
random_node(Type) ->
  random_node(all_nodes(Type)).

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
  NodeTable =
    lists:foldl(
      fun(Node, Res) ->
        [Memory | _] = mnesia:dirty_read({ecm_nodeinfo, Node}),
        {_, _, Total_Memory, UpLoad_Time} = Memory,
        Current_Time = misc:now(),
        Distance_Time = Current_Time - UpLoad_Time,
        Limit_Time = 60 * 2 * 1000,
        case Distance_Time < Limit_Time of
          true -> [{Node, Total_Memory} | Res];
          _ -> Res
        end
      end, [], Nodes
    ),
  OrderNodeTab =
    lists:sort(
      fun(Node_Low, Node_High) ->
        {_, Memory_Low} = Node_Low,
        {_, Memory_High} = Node_High,
        Memory_Low < Memory_High
      end, NodeTable
    ),
  {_, IdeaMem} = lists:nth(1, OrderNodeTab),
  DisMemory = 100 * 1024 * 1024,
  PendNodeTab =
    lists:foldl(
      fun(Node, Res) ->
        {_, Total_Memory} = Node,
        case erlang:abs(IdeaMem - Total_Memory) =< DisMemory of
          true ->
            [Node | Res];
          _ -> Res
        end
      end, [], OrderNodeTab
    ),
  Index = rand:uniform(length(PendNodeTab)),
  {Node, _} = lists:nth(Index, PendNodeTab),
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
  case all_nodes(Type) of
    {Type, Nodes} when is_list(Nodes), length(Nodes) > 0 ->
      wait_dependencies(Others, Times, MaxTimes);
    _ ->
      receive after 1000 -> ok end,
      wait_dependencies(Dependent, Times + 1, MaxTimes)
  end.

table_name(Type) ->
  table_name(ets:lookup(ecm_table_names, Type), Type).
table_name([{_, Name}], _Type) ->
  Name;
table_name([], Type) ->
  Name = list_to_atom(lists:concat(["ecm_", Type])),
  true = ets:insert(ecm_table_names, {Type, Name}),
  Name.

on_add_table_copy({atomic, ok}, Table, _TabDef) ->
  ok = mnesia:wait_for_tables([schema, Table], 60000);
on_add_table_copy({aborted, {no_exists, _}}, Table, TabDef) ->
  on_add_table_copy(mnesia:create_table(Table, TabDef), Table, TabDef);
on_add_table_copy({aborted, {already_exists, Table, _}}, Table, _) ->
  ok = mnesia:wait_for_tables([schema, Table], 60000);
on_add_table_copy({aborted, {already_exists, Table}}, Table, _) ->
  ok = mnesia:wait_for_tables([schema, Table], 60000);
on_add_table_copy(Reason, _, _) ->
  Reason.

sync_other_tables() ->
  {atomic, Tables} = mnesia:transaction(
    fun() ->
      [T || T <- mnesia:all_keys(ecm_nodes), T =/= master]
    end),
  ok = lists:foreach(fun sync_table/1, Tables).

foreach_pid(Type, Function) ->
  Table = table_name(Type),
  case catch mnesia:transaction(
    fun mnesia:foldl/3,
    [
      fun({_, _, Pid, _, _}, ok) ->
        ok = Function(Pid)
      end,
      ok,
      Table
    ]
  ) of
    {atomic, ok} ->
      ok;
    Error ->
      error_logger:error_report(Error)
  end.
