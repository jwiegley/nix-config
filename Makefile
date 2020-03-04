HOSTNAME   = vulcan
REMOTES	   = hermes athena
GIT_REMOTE = jwiegley
ENVS	   = emacs26Env emacsERCEnv ledgerPy2Env ledgerPy3Env # emacsHEADEnv

# Lazily evaluated variables; expensive to compute, but we only want it do it
# when first necessary.
GIT_DATE   = git --git-dir=nixpkgs/.git show -s --format=%cd --date=format:%Y%m%d_%H%M%S
HEAD_DATE  = $(eval HEAD_DATE := $(shell $(GIT_DATE) HEAD))$(HEAD_DATE)
LKG_DATE   = $(eval LKG_DATE  := $(shell $(GIT_DATE) last-known-good))$(LKG_DATE)

ifeq ($(NOCACHE),true)
NIXOPTS	   = --option build-use-substitutes false	\
	     --option substituters ''			\
	     --option builders ''
else
NIXOPTS	   =
endif
NIX_CONF   = $(HOME)/src/nix
NIXPATH	   = $(NIX_PATH):localconfig=$(NIX_CONF)/config/$(HOSTNAME).nix
PRENIX	   = PATH=$(BUILD_PATH)/sw/bin:$(PATH) NIX_PATH=$(NIXPATH)

NIX	   = $(PRENIX) nix
NIX_BUILD  = $(PRENIX) nix-build
NIX_ENV	   = $(PRENIX) nix-env
NIX_STORE  = $(PRENIX) nix-store
NIX_GC	   = $(PRENIX) nix-collect-garbage

BUILD_ARGS = $(NIXOPTS) --keep-going --argstr version $(HEAD_DATE)
ifeq ($(REALBUILDPATH),true)
BUILD_PATH = $(eval BUILD_PATH :=					\
		$(shell echo NIX_PATH=$(NIXPATH) nix-build $(BUILD_ARGS)))$(BUILD_PATH)
else
BUILD_PATH = /run/current-system
endif

DARWIN_REBUILD = $(PRENIX) $(BUILD_PATH)/sw/bin/darwin-rebuild
HOME_MANAGER   = $(PRENIX) HOME_MANAGER_CONFIG=$(NIX_CONF)/config/home.nix	\
			   $(BUILD_PATH)/sw/bin/home-manager

all: rebuild

%-all: %
	for host in $(REMOTES); do					\
	    ssh $$host "make -C $(NIX_CONF) HOSTNAME=$$host $<";	\
	done

build:
	$(NIX) build -f . $(BUILD_ARGS)
	@rm -f result*

darwin-switch:
	$(DARWIN_REBUILD) switch -Q
	@echo "Darwin generation: $$($(DARWIN_REBUILD) --list-generations | tail -1)"

home-switch:
	$(HOME_MANAGER) switch
	@echo "Home generation: $$($(HOME_MANAGER) generations | head -1)"
	@for file in $(HOME)/.config/fetchmail/config		\
		     $(HOME)/.config/fetchmail/config-lists; do	\
	    cp -pL $$file $$file.copy;				\
	    chmod 0600 $$file.copy;				\
	done

home-news:
	$(HOME_MANAGER) news

switch: darwin-switch home-switch

env:
	@for i in $(ENVS); do							\
	    echo Updating $$i;							\
	    $(NIX_ENV) -f '<darwin>' -u --leq -Q -k $(NIXOPTS) -A pkgs.$$i ;	\
	done
	@echo "Nix generation: $$($(NIX_ENV) --list-generations | tail -1)"

rebuild: build switch env

pull:
	(cd darwin		   && git pull --rebase)
	(cd home-manager	   && git pull --rebase)
	(cd overlays/emacs-overlay && git pull --rebase)
	(cd nixpkgs		   && git pull --rebase)

tag-before:
	git --git-dir=nixpkgs/.git branch -f before-update HEAD

tag-working:
	git --git-dir=nixpkgs/.git branch -f last-known-good before-update
	git --git-dir=nixpkgs/.git branch -D before-update
	git --git-dir=nixpkgs/.git tag -f known-good-$(LKG_DATE) last-known-good

mirror:
	git --git-dir=nixpkgs/.git push $(GIT_REMOTE) -f master:master
	git --git-dir=nixpkgs/.git push $(GIT_REMOTE) -f unstable:unstable
	git --git-dir=nixpkgs/.git push $(GIT_REMOTE) -f last-known-good:last-known-good
	git --git-dir=nixpkgs/.git push -f --tags $(GIT_REMOTE)
	git --git-dir=darwin/.git push --mirror $(GIT_REMOTE)
	git --git-dir=home-manager/.git push --mirror $(GIT_REMOTE)
	git --git-dir=overlays/emacs-overlay/.git push --mirror $(GIT_REMOTE)

working: tag-working mirror

update: tag-before pull build switch env working

sizes:
	sizes /nix/store

check:
	$(NIX_STORE) --verify --repair --check-contents

copy-nix:
	@for host in $(REMOTES); do			\
	    $(NIX) copy --keep-going --to ssh://$$host	\
	        $(HOME)/.nix-profile $(BUILD_PATH);	\
	done

copy: copy-nix
	@for host in $(REMOTES); do		\
	    push -h $(HOSTNAME) -f src $$host;	\
	done

CACHE_DIR = /Volumes/Backup/nix

cache:
	nix copy --all --keep-going --to "file://$(CACHE_DIR)"
	-quickping 192.168.1.65 &&							\
	    ssh hermes test -d /Volumes/G-DRIVE/nix &&					\
	    rsync -a --delete /Volumes/Backup/nix/ hermes:/Volumes/G-DRIVE/nix/

remove-build-products:
	find $(HOME)/Documents $(HOME)/src		\
	    \( -name '.cargo-home' -type d -o		\
	       -name '.direnv' -type d -o		\
	       -name '.envrc.cache' -type f -o		\
	       -name '.ghc.*' -o			\
	       -name 'cabal.project.local*' -type f -o	\
	       -name 'dist' -type d -o			\
	       -name 'dist-newstyle' -type d -o		\
	       -name 'result*' -type l -o		\
	       -name 'target' -type d \) -print0	\
	    | xargs -P4 -0 /bin/rm -fr

MAX_AGE = 14

gc:
	$(NIX_ENV) --delete-generations						\
	    $(shell $(NIX_ENV) --list-generations | field 1 | head -n -$(MAX_AGE))
	$(NIX_ENV) -p /nix/var/nix/profiles/system --delete-generations		\
	    $(shell $(NIX_ENV) -p /nix/var/nix/profiles/system			\
				 --list-generations | field 1 | head -n -$(MAX_AGE))
	$(NIX_GC) --delete-older-than $(MAX_AGE)d

gc-old: remove-build-products
	$(NIX_ENV) --delete-generations						\
	    $(shell $(NIX_ENV) --list-generations | field 1 | head -n -1)
	$(NIX_ENV) -p /nix/var/nix/profiles/system --delete-generations		\
	    $(shell $(NIX_ENV) -p /nix/var/nix/profiles/system			\
				 --list-generations | field 1 | head -n -1)
	$(NIX_GC) --delete-old

clean: gc check

fullclean: gc-old check

# These rules are used for debugging only

tools:
	@PATH=$(BUILD_PATH)/sw/bin:$(PATH)	\
	    which				\
		field				\
		find				\
		git				\
		head				\
		make				\
		nix-build			\
		nix-env				\
		sort				\
		sudo				\
		uniq

opts:
	@echo export NIXOPTS=$(NIXOPTS)
	@echo export NIX_PATH=$(NIXPATH)
