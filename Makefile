## This a standard template recursive makefile I use, with install/test stuff, etc commented out

SHELL = /bin/sh
#INSTALL = /usr/bin/install
#INSTALL_PROGRAM = $(INSTALL)
#INSTALL_DATA = $(INSTALL) -m 644
include Makefile.conf

DIRS = hernia pkgs doc
BUILDDIRS = $(DIRS:%=build-%)
#INSTALLDIRS = $(DIRS:%=install-%)
#TESTDIRS = $(DIRS:%=test-%)
CLEANDIRS = $(DIRS:%=clean-%)

##

#.PHONY: $(DIRS) $(BUILDDIRS) $(INSTALLDIRS) $(TESTDIRS) $(CLEANDIRS) all install test clean
.PHONY: $(DIRS) $(BUILDDIRS) $(CLEANDIRS) all clean

##

all: $(BUILDDIRS) external_vars.sh zonefile.txt

#install: $(INSTALLDIRS)

#test: $(TESTDIRS)

clean: $(CLEANDIRS)

##

$(DIRS): $(BUILDDIRS)

$(BUILDDIRS):
	$(MAKE) -C $(@:build-%=%)

#$(INSTALLDIRS):
#	$(MAKE) -C $(@:install-%=%) install

#$(TESTDIRS):
#	$(MAKE) -C $(@:test-%=%) test

$(CLEANDIRS):
	$(MAKE) -C $(@:clean-%=%) clean

# ordering: for example when the utils need the libraries in dev built first...
#build-utils: build-dev

external_vars.sh: external_vars.sh.template
	printf '****** external_vars.sh either doesn'\''t exist or is older than external_vars.sh.template - fix that manually before rerunning make.\n'
	false

zonefile.txt: zonefile.txt.template
	printf '****** zonefile.txt either doesn'\''t exist or is older than zonefile.txt.template - fix that manually before rerunning make.\n'
	false
