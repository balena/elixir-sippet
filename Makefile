.PHONY: all clean distclean

REBAR=`sh -c "PATH='$(PATH)':support which rebar\
	|| support/getrebar || echo false"`

all:
	@$(REBAR) compile

clean:
	@$(REBAR) clean

distclean: clean
	@rm -fr priv
