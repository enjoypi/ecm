PROJECT = ecm

include erlang.mk

.DEFAULT_GOAL = ct

ERLC_OPTS := +debug_info +native -Werror -v

clean::
	@$(RM) -r logs

ct:: CT_OPTS := -env ERL_LIBS $(PWD) -ctmaster -sname 'ecm_ct_master' -eval "ct_master:run(\"ct_master.spec\")" -erl_args -config test/ecm.config

