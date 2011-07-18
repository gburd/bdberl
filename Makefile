BDB_VERSION=5.1.25
BDB_DIST=db-$(BDB_VERSION).tar.gz
BDB_LOCAL_DIST=c_src/$(BDB_DIST)
BDB_LOCAL_LIB=c_src/system/lib/libdb.a
BDB_DIST_URL=http://download.oracle.com/berkeley-db/$(BDB_DIST)

ERL=erl
ERL_FLAGS=+A10
REBAR=./rebar
REBAR_FLAGS=

all: $(BDB_LOCAL_LIB)
	ERL_FLAGS=$(ERL_FLAGS) $(REBAR) $(REBAR_FLAGS) compile eunit ct

$(BDB_LOCAL_DIST):
	ERL_FLAGS=$(ERL_FLAGS) $(ERL) -noshell -s inets -eval 'httpc:request(get, {"$(BDB_DIST_URL)", []}, [], [{stream, "$(BDB_LOCAL_DIST)"}])' -s init stop

$(BDB_LOCAL_LIB): $(BDB_LOCAL_DIST)
	c_src/buildlib.sh
clean: 
	$(REBAR) $(REBAR_FLAGS) clean

distclean: clean
	-rm -rf $(BDB_LOCAL_DIST)
	-rm -rf c_src/sources 
	-rm -rf priv
	-rm -rf logs
