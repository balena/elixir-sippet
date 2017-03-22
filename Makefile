.PHONY: all dev clean doc test dialyzer check eunit qc

REBAR=`sh -c "PATH='$(PATH)':support which rebar\
	|| support/getrebar || echo false"`

all:
	@$(REBAR) compile

debug:
	@sh -c "DEBUG=1 $(REBAR) compile -DDEV -DDEBUG"

dev:
	@$(REBAR) compile -DDEV

doc:
	@$(REBAR) doc

clean:
	@$(REBAR) clean

distclean: clean
	@rm -fr priv

check: test dialyzer

test: eunit qc

eunit:
	@$(REBAR) eunit

qc:
	@$(REBAR) qc

dialyzer:
	@dialyzer -n -nn ebin
