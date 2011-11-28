
ERL             ?=erl
CT_RUN          ?=ct_run
ERL_FLAGS       ?=+A10
REBAR_FLAGS     :=

all: $(BDB_LOCAL_LIB)
	ERL_FLAGS=$(ERL_FLAGS) $(REBAR) $(REBAR_FLAGS) compile

test: tests

tests:
	@ $(REBAR) $(REBAR_FLAGS) eunit ct

thrash-test:
	@ $(CT_RUN) -pa test/ -suite thrash_SUITE

clean:
	$(REBAR) $(REBAR_FLAGS) clean
	-rm test/*.beam

distclean: clean
	-make -C c_src clean
	-rm -rf c_src/sources
	-rm -rf priv
	-rm -rf logs

include rebar.mk
