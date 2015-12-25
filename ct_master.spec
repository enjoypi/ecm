%%-*- mode: erlang -*-

{define, 'ROOT', "ECM_PATH" }.
{define, 'HOST', 'HOSTNAME' }.
{define, 'ERL_FLAGS', "-pa 'ROOT'/ebin/ -pa 'ROOT'/test/ -config 'ROOT'/test/ecm.config"}.

{ node, master1, 'ecm_master1@HOST'}.
{ node, master2, 'ecm_master2@HOST'}.
{ node, test1, 'ecm_test1@HOST'}.
{ node, test2, 'ecm_test2@HOST'}.
{ node, test3, 'ecm_test3@HOST'}.
{ node, test4, 'ecm_test4@HOST'}.
{ node, test5, 'ecm_test5@HOST'}.
{ node, test6, 'ecm_test6@HOST'}.
{ node, test7, 'ecm_test7@HOST'}.
{ node, test8, 'ecm_test8@HOST'}.
{ node, test9, 'ecm_test9@HOST'}.

{init, [master1, master2],
 [
  {node_start, [
                {monitor_master, true},
                {erl_flags, "'ERL_FLAGS' -ecm node_type master -eval \"ok=application:start(ecm),ok=ecm:finish_start().\""}
               ]},
  {kill_if_fail, true}
 ]}.

{init, [test1 ,test2, test3, test4, test5, test6, test7, test8, test9],
 [
  {node_start, [
                {monitor_master, true},
                {erl_flags, "'ERL_FLAGS' -ecm node_type test -ecm test_sup ecm_test_sup -eval \"ok=application:start(ecm),ok=ecm:finish_start().\""}
               ]},
  {kill_if_fail, true}
 ]}.

{logdir, all_nodes, "./logs/"}.
{logdir, master, "./logs/"}.

{suites, master1, "./", [ecm_master1_SUITE]}.
{suites, master2, "./", [ecm_master2_SUITE]}.
{suites, test1, "./", [ecm_test1_SUITE]}.
{suites, test2, "./", [ecm_test2_SUITE]}.
{suites, test3, "./", [ecm_test3_SUITE]}.
{suites, test4, "./", [ecm_test4_SUITE]}.
{suites, test5, "./", [ecm_test5_SUITE]}.
{suites, test6, "./", [ecm_test6_SUITE]}.
{suites, test7, "./", [ecm_test7_SUITE]}.
{suites, test8, "./", [ecm_test8_SUITE]}.
{suites, test9, "./", [ecm_test9_SUITE]}.

{verbosity, 99}.
