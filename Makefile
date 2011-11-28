
ERL             ?=erl
ERL_FLAGS       ?=+A10
REBAR_FLAGS     :=

all: $(BDB_LOCAL_LIB)
	ERL_FLAGS=$(ERL_FLAGS) $(REBAR) $(REBAR_FLAGS) compile

test: tests

tests:
	@ $(REBAR) $(REBAR_FLAGS) eunit ct

clean:
	$(REBAR) $(REBAR_FLAGS) clean
	-rm test/*.beam

distclean: clean
	-rm -rf $(BDB_LOCAL_DIST)
	-rm -rf c_src/sources
	-rm -rf priv
	-rm -rf logs

include rebar.mk

