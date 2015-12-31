%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(ecm_db).

%% API
-export([
  all_nodes/0,
  delete/1,
  finish_start/1,
  foreach_pid/2,
  get/2,
  nodes/1,
  set/4,
  size/1,
  start/2,
  sync_table/1,
  sync_table/2,
  select/1,
  all/0
]).

%% ecm_Type
-record(ecm_process, {id, pid, node}).

%% tables for masters
-record(ecm_nodes, {type, node}).
-record(ecm_processes, {pid, table, id, node_id}).

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
  lists:map(fun nodes/1, Types).

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
delete(Pid) when is_pid(Pid) ->
  case catch mnesia:dirty_read(ecm_processes, Pid) of
    [{ecm_processes, Pid, Table, Id, _}] ->
      case catch mnesia:dirty_read(Table, Id) of
        %% must match Pid
        [{Table, Id, Pid, _}] ->
          ok = mnesia:dirty_delete(Table, Id);
        _ ->
          ok
      end;
    _ ->
      ok
  end,
  %% delete whatever
  ok = mnesia:dirty_delete(ecm_processes, Pid).

all() ->
  mnesia:dirty_all_keys(ecm_processes).

select(Flag) ->
  MatchSpec = [{{'_','$1','_','_','$2'}, [{'=:=','$2',{const,Flag}}], ['$1']}],
  mnesia:dirty_select(ecm_processes,MatchSpec).


%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
finish_start(Type) ->
  ok = mnesia:wait_for_tables([ecm_nodes], 60000),
  ok = sync_other_tables(),
  {atomic, _} = mnesia:transaction(
    fun() ->
      ok = mnesia:write(#ecm_nodes{type = Type, node = node()})
    end),
  ok.

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
foreach_pid(Type, Function) ->
  Table = table_name(Type),
  {atomic, ok} = mnesia:transaction(
    fun mnesia:foldl/3,
    [
      fun({_, _, Pid, _}, ok) ->
        ok = Function(Pid)
      end,
      ok,
      Table
    ]
  ),
  ok.

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
get(Type, Id) ->
  Table = table_name(Type),
  case catch mnesia:dirty_read(Table, Id) of
    [{_, _, Pid, _} | _] ->
      {ok, Pid};
    _ ->
      undefined
  end.

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
nodes(Type) ->
  Records =
    case catch mnesia:dirty_read(ecm_nodes, Type) of
      R when is_list(R) ->
        R;
      _ ->
        []
    end,
  {Type, [Node || {ecm_nodes, _Type, Node} <- Records]}.

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
set(Type, Id, Node, Pid) ->
  Table = table_name(Type),
  Result =
    case catch mnesia:dirty_read(Table, Id) of
      [R = {Table, Id, Pid, _}] ->
        {ok, R};
      _ ->
        ok
    end,
  NodeString = atom_to_list(Node),
  [Flag,_Host] = string:tokens(NodeString,"@"),
  ok = mnesia:dirty_write({Table, Id, Pid, Node}),
  ok = mnesia:dirty_write({ecm_processes, Pid, Table, Id, Flag}),
  ok = ecm_process_server:monitor(Pid),
  Result.

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
size(Type) ->
  ets:info(table_name(Type), size).

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
start(Type, Masters) ->
  ok = application:ensure_started(mnesia),
  {ok, _} = mnesia:change_config(extra_db_nodes, Masters),
  ok = mnesia:wait_for_tables([schema], 60000),
  ok = sync_table(Type).

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
sync_table(master) ->
  {ok, Masters} = application:get_env(ecm, masters),
  NodesTabDef = [
    {attributes, record_info(fields, ecm_nodes)},
    {ram_copies, Masters},
    {type, bag}
  ],
  ok = sync_table(ecm_nodes, NodesTabDef),
  ProcessesTabDef = [
    {attributes, record_info(fields, ecm_processes)},
    {ram_copies, Masters},
    {type, set}
  ],
  ok = sync_table(ecm_processes, ProcessesTabDef);
sync_table(Type) ->
  %% can create atom
  Table = list_to_atom(lists:concat(["ecm_", Type])),
  Nodes = [node() | nodes()],
  TabDef = [
    {attributes, record_info(fields, ecm_process)},
    {ram_copies, Nodes},
    {type, set}
  ],
  ok = sync_table(Table, TabDef).

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------
sync_table(Table, TabDef) ->
  on_add_table_copy(mnesia:add_table_copy(Table, node(), ram_copies), Table, TabDef).

%%%===================================================================
%%% Internal functions
%%%===================================================================
on_add_table_copy({atomic, ok}, Table, _TabDef) ->
  ok = mnesia:wait_for_tables([schema, Table], 60000);
on_add_table_copy({aborted, {no_exists, _}}, Table, TabDef) ->
  {atomic, ok} = mnesia:create_table(Table, TabDef),
  ok;
on_add_table_copy({aborted, {already_exists, Table, _}}, Table, _) ->
  ok = mnesia:wait_for_tables([schema, Table], 60000);
on_add_table_copy(Reason, _, _) ->
  Reason.

sync_other_tables() ->
  {atomic, Tables} = mnesia:transaction(
    fun() ->
      [T || T <- mnesia:all_keys(ecm_nodes), T =/= master]
    end),
  ok = lists:foreach(fun sync_table/1, Tables).

table_name(Type) ->
  %% won't create atom
  list_to_existing_atom(lists:concat(["ecm_", Type])).

