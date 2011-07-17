all:  c_src/system/lib/libdb.a 
	./rebar compile eunit ct

c_src/system/lib/libdb.a:
	c_src/buildlib.sh
clean: 
	./rebar clean

