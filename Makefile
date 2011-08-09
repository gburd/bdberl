all: compile

compile:
	@ $(REBAR) compile

tests:
	@ $(REBAR) ct

clean:
	@ $(REBAR) clean
	@ rm -rf ./logs

include rebar.mk