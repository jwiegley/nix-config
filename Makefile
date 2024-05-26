HOSTNAME   = vulcan
REMOTES	   = hermes
GIT_REMOTE = jwiegley
MAX_AGE	   = 14
NIX_CONF   = $(HOME)/src/nix
NIXOPTS	   =

ifneq ($(CACHE),)
NIXOPTS	  := $(NIXOPTS) --substituters 'ssh://$(CACHE)'
endif
ifneq ($(BUILDER),)
NIXOPTS	  := $(NIXOPTS) --option builders 'ssh://$(BUILDER)'
endif

# When building with the Makefile, rather than calling darwin-rebuild
# directly, we set the NIX_PATH to point at whatever is the latest pull of the
# various projects used to build this Nix configuration. See nix.nixPath in
# darwin.nix for the system definition of the NIX_PATH, which relies on
# whichever versions of the below were used to build that generation.
NIX_PATH   = $(HOME)/.nix-defexpr/channels
NIX_PATH  := $(NIX_PATH):ssh-auth-sock=$(HOME)/.config/gnupg/S.gpg-agent.ssh
NIX_PATH  := $(NIX_PATH):ssh-config-file=$(HOME)/.ssh/config

BUILD_ARGS = $(NIXOPTS) --keep-going

PRENIX	  := NIX_PATH=$(NIX_PATH)

all: switch

%-all: %
	@for host in $(REMOTES); do						\
	    ssh $$host "CACHE=$(HOSTNAME) NIX_CONF=$(NIX_CONF) u $$host $<";	\
	done

define announce
	@echo
	@echo '┌────────────────────────────────────────────────────────────────────────────┐'
	@echo -n '│ >>> $(1)'
	@printf "%$$((72 - $(shell echo '$(1)' | wc -c)))s│\n"
	@echo '└────────────────────────────────────────────────────────────────────────────┘'
endef

test:
	$(call announce,this is a test)

tools:
	@echo HOSTNAME=$(HOSTNAME)
	@echo CACHE=$(CACHE)
	@echo BUILDER=$(BUILDER)

	@echo export PATH=$(PATH)
	@echo export NIXOPTS=$(NIXOPTS)
	@echo export NIX_PATH=$(NIX_PATH)
	@echo export BUILD_ARGS=$(BUILD_ARGS)

	which   field				\
		find				\
		git				\
		head				\
		make				\
		nix				\
		nix-build			\
		nix-env				\
		sort				\
		uniq

# nix --extra-experimental-features repl-flake repl .#darwinConfigurations.vulcan.pkgs

build:
	$(call announce,darwin-rebuild build --impure --flake .#$(HOSTNAME))
	@$(PRENIX) darwin-rebuild build --impure --flake .#$(HOSTNAME)
	@rm -f result*

switch:
	$(call announce,darwin-rebuild switch --impure --flake .#$(HOSTNAME))
	@$(PRENIX) darwin-rebuild switch --impure --flake .#$(HOSTNAME)
	brew upgrade
	@echo "Darwin generation: $$($(PRENIX) darwin-rebuild --list-generations | tail -1)"

pull:
	$(call announce,git pull)
	nix flake lock --update-input nixpkgs
	nix flake lock --update-input darwin
	nix flake lock --update-input home-manager
	brew update

update: pull switch travel-ready

update-sync: update copy switch-all travel-ready-all

########################################################################

copy-src:
	$(call announce,pushme)
	@for host in $(REMOTES); do				\
	    push -f Home,src,doc,kadena $$host;			\
	done

copy: copy-src

########################################################################

define delete-generations
	$(PRENIX) nix-env $(1) --delete-generations			\
	    $(shell $(PRENIX) nix-env $(1)				\
		--list-generations | field 1 | head -n -$(2))
endef

define delete-generations-all
	$(call delete-generations,,$(1))
	$(call delete-generations,-p /nix/var/nix/profiles/system,$(1))
endef

check:
	$(call announce,nix store verify --all)
	@$(PRENIX) nix-store --verify --repair --check-contents
	@$(PRENIX) nix store verify --all

sizes:
	df -H /nix 2>&1 | grep /dev

gc:
	$(call delete-generations-all,$(MAX_AGE))
	$(PRENIX) nix-collect-garbage --delete-older-than $(MAX_AGE)d
	sudo $(PRENIX) nix-collect-garbage --delete-older-than $(MAX_AGE)d

clean: gc

gc-old:
	$(call delete-generations-all,1)
	$(PRENIX) nix-collect-garbage --delete-old
	sudo $(PRENIX) nix-collect-garbage --delete-old

purge: gc-old

sign:
	$(call announce,nix store sign -k "<key>" --all)
	@$(PRENIX) nix store sign -k $(HOME)/.config/gnupg/nix-signing-key.sec --all

PROJECTS = $(HOME)/.config/projects

# TRAVEL_FLAG = --no-cache
TRAVEL_FLAG =

travel-ready:
	$(call announce,travel-ready)
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)")
	@for dir in "$${projects[@]}"; do			\
	    echo "Updating direnv on $(HOSTNAME) for ~/$$dir";	\
	    (cd ~/$$dir &&					\
             if [[ $(HOSTNAME) == athena ]]; then		\
                 unset BUILDER CACHE;				\
	         $(NIX_CONF)/bin/de $(TRAVEL_FLAG);		\
             elif [[ $(HOSTNAME) == hermes ]]; then		\
                 unset BUILDER CACHE;				\
	         $(NIX_CONF)/bin/de $(TRAVEL_FLAG);		\
             else						\
	         unset BUILDER;					\
		 CACHE=$(CACHE);				\
	         $(NIX_CONF)/bin/de $(TRAVEL_FLAG);		\
	     fi);						\
	done

.ONESHELL:
