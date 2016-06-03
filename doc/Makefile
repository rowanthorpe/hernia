##

#.PHONY: all install test clean
.PHONY: all clean

##

all: README.html TODO.html

#install: all

#test: all

clean:
	rm -f README.html TODO.html *~

##

README.html: README.md
	printf '<!DOCTYPE html>\n<html><head><title>README</title></head><body>\n' >README.html
	markdown_py -o html5 README.md >>README.html
	printf '\n</body></html>' >>README.html
	printf 'README.html has been updated, add it for commit\n' >&2

TODO.html: TODO.md
	printf '<!DOCTYPE html>\n<html><head><title>README</title></head><body>\n' >TODO.html
	markdown_py -o html5 TODO.md >>TODO.html
	printf '\n</body></html>' >>TODO.html
	printf 'TODO.html has been updated, add it for commit\n' >&2
