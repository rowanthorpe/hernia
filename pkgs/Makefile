sources = $(wildcard */*.control)
packages = $(sources:.control=_all.deb)

##

#.PHONY: all install test clean
.PHONY: all clean

##

all: $(packages)

#install: all

#test: all

clean:
	rm -f */*_all.deb *~ */*~

##

%_all.deb: %.control
	cp $< .
	equivs-build `basename $<`
	mv -v `basename $@` `dirname $@`
	rm -f `basename $<`
	printf '%s has been updated, add it for commit\n' `basename $@` >&2
