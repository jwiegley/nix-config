HOSTNAME   = vulcan
REMOTES	   = clio
GIT_REMOTE = jwiegley
MAX_AGE	   = 14
NIX_CONF   = $(HOME)/src/nix
NIXOPTS	   =

ifneq ($(BUILDER),)
NIXOPTS	  := $(NIXOPTS) --option builders 'ssh://$(BUILDER)'
endif

all: switch

%-all: %
	@for host in $(REMOTES); do				\
	    ssh $$host "NIX_CONF=$(NIX_CONF) u $$host $<";	\
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
	@echo BUILDER=$(BUILDER)

	@echo export PATH=$(PATH)
	@echo export NIXOPTS=$(NIXOPTS)

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

repl:
	nix --extra-experimental-features repl-flake \
	    repl .#darwinConfigurations.$(HOSTNAME).pkgs

build:
	$(call announce,darwin-rebuild build --impure --flake .#$(HOSTNAME))
	@darwin-rebuild build --impure --flake .#$(HOSTNAME)
	@rm -f result*

switch:
	$(call announce,darwin-rebuild switch --impure --flake .#$(HOSTNAME))
	@darwin-rebuild switch --impure --flake .#$(HOSTNAME)
	@echo "Darwin generation: $$(darwin-rebuild --list-generations | tail -1)"

update:
	$(call announce,nix flake update --commit-lock-file && brew update)
	nix flake update --commit-lock-file
	@for project in $(shell grep "^[^#]" $(HOME)/.config/projects); do	\
	    ( cd $(HOME)/$$project ;						\
	      echo "### $(HOME)/$$project" ;					\
	      nix flake update --commit-lock-file				\
	    );									\
	done
	@if [[ -f /opt/homebrew/bin/brew ]]; then	\
	    eval "$(/opt/homebrew/bin/brew shellenv)";	\
	elif [[ -f /usr/local/bin/brew ]]; then		\
	    eval "$(/usr/local/bin/brew shellenv)";	\
	fi
	brew update

upgrade-tasks: switch travel-ready
	@if [[ -f /opt/homebrew/bin/brew ]]; then	\
	    eval "$(/opt/homebrew/bin/brew shellenv)";	\
	elif [[ -f /usr/local/bin/brew ]]; then		\
	    eval "$(/usr/local/bin/brew shellenv)";	\
	fi
	brew upgrade --greedy

upgrade: update upgrade-tasks check

changes:
	@for project in $(shell grep "^[^#]" $(HOME)/.config/projects); do	\
	    ( cd $(HOME)/$$project ;						\
	      echo "### $(HOME)/$$project" ;					\
	      changes								\
	    );									\
	done

########################################################################

copy:
	$(call announce,copy)
	@for host in $(REMOTES); do						\
	    nix copy --to "ssh-ng://$$host"					\
	        $(HOME)/.local/state/nix/profiles/profile;			\
	    for project in $(shell grep "^[^#]" $(HOME)/.config/projects); do	\
	        echo $$project;							\
	        ( cd $(HOME)/$$project ;					\
	          if [[ -f .envrc.cache ]]; then				\
	              source <(direnv apply_dump .envrc.cache) ;		\
	              if [[ -n "$$buildInputs" ]]; then				\
	                  eval nix copy --to ssh-ng://$$host $$buildInputs;	\
	              fi;							\
	          fi								\
	        );								\
	    done;								\
	done

########################################################################

define delete-generations
	nix-env $(1) --delete-generations			\
	    $(shell nix-env $(1)				\
		--list-generations | field 1 | head -n -$(2))
endef

define delete-generations-all
	$(call delete-generations,,$(1))
	$(call delete-generations,-p /nix/var/nix/profiles/system,$(1))
endef

check:
	$(call announce,nix store verify --no-trust --repair --all)
	@nix store verify --no-trust --repair --all

sizes:
	df -H /nix 2>&1 | grep /dev

clean:
	$(call delete-generations-all,$(MAX_AGE))
	nix-collect-garbage --delete-older-than $(MAX_AGE)d
	sudo nix-collect-garbage --delete-older-than $(MAX_AGE)d

purge:
	$(call delete-generations-all,1)
	nix-collect-garbage --delete-old
	sudo nix-collect-garbage --delete-old

sign:
	$(call announce,nix store sign -k "<key>" --all)
	@nix store sign -k $(HOME)/.config/gnupg/nix-signing-key.sec --all

PROJECTS = $(HOME)/.config/projects

travel-ready:
	$(call announce,travel-ready)
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)")
	@for dir in "$${projects[@]}"; do			\
	    echo "Updating direnv on $(HOSTNAME) for ~/$$dir";	\
	    (cd ~/$$dir &&					\
             rm -f .envrc .envrc.cache;				\
             if [[ $(HOSTNAME) == athena ]]; then		\
	         $(NIX_CONF)/bin/de;				\
             elif [[ $(HOSTNAME) == hermes ]]; then		\
	         $(NIX_CONF)/bin/de;				\
             elif [[ $(HOSTNAME) == hera ]]; then		\
	         $(NIX_CONF)/bin/de;				\
             elif [[ $(HOSTNAME) == clio ]]; then		\
	         $(NIX_CONF)/bin/de;				\
             else						\
	         unset BUILDER;					\
	         $(NIX_CONF)/bin/de;				\
	     fi);						\
	done

.ONESHELL:
