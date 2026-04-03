HOSTNAME   ?= $(shell myhost)
REMOTES	   = clio
GIT_REMOTE = jwiegley
MAX_AGE	   = 28
NIX_CONF   = $(HOME)/src/nix
NIXOPTS	   =
PROJECTS   = $(HOME)/.config/projects

ifneq ($(BUILDER),)
NIXOPTS	  := $(NIXOPTS) --option builders 'ssh://$(BUILDER)'
endif

.PHONY: all verify-inputs lock-local build switch update update-projects upgrade-tasks upgrade \
	changes copy check sizes clean purge sign travel-ready test tools repl

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

verify-inputs:
	$(call announce,Verifying local git inputs for NAR hash safety)
	@errfile=$$(mktemp); \
	python3 -c '\
	import json; \
	lock = json.load(open("flake.lock")); \
	nodes = lock["nodes"]; \
	[print(nodes.get(k if isinstance(k, str) else n, {}).get("locked", {}).get("url", "")) \
	 for n, k in nodes["root"]["inputs"].items() \
	 if nodes.get(k if isinstance(k, str) else n, {}).get("locked", {}).get("type") == "git" \
	 and "file://" in nodes.get(k if isinstance(k, str) else n, {}).get("locked", {}).get("url", "")]' \
	| sed 's|file://||' \
	| while IFS= read -r repo; do \
	    bad=$$(git -C "$$repo" ls-files -v 2>/dev/null | grep -E '^[shS] '); \
	    if [ -n "$$bad" ]; then \
	        echo "ERROR: $$repo has skip-worktree/assume-unchanged files:" | tee -a "$$errfile"; \
	        echo "$$bad" | tee -a "$$errfile"; \
	        echo "Fix: git -C $$repo update-index --no-skip-worktree --no-assume-unchanged <files>" | tee -a "$$errfile"; \
	        echo "Then: git -C $$repo checkout -- <files>" | tee -a "$$errfile"; \
	    fi; \
	    uninit=$$(git -C "$$repo" submodule status 2>/dev/null | grep '^-'); \
	    if [ -n "$$uninit" ]; then \
	        echo "ERROR: $$repo has uninitialized submodules:" | tee -a "$$errfile"; \
	        echo "$$uninit" | tee -a "$$errfile"; \
	        echo "Fix: cd $$repo && git submodule update --init" | tee -a "$$errfile"; \
	    fi; \
	    gitlinks=$$(git -C "$$repo" ls-files --stage 2>/dev/null | grep '^160000'); \
	    if [ -n "$$gitlinks" ]; then \
	        echo "WARNING: $$repo has submodules (gitlinks) that may cause NAR hash divergence:"; \
	        echo "$$gitlinks"; \
	        echo "Consider: remove submodules or add ?submodules=1 to the flake input URL"; \
	    fi; \
	done; \
	if [ -s "$$errfile" ]; then \
	    echo ""; \
	    echo "NAR hash mismatches will occur until the above are fixed."; \
	    echo "See: nix flake update uses filesystem, darwin-rebuild uses git archive."; \
	    rm -f "$$errfile"; \
	    exit 1; \
	fi; \
	rm -f "$$errfile"

lock-local: verify-inputs
	$(call announce,Re-locking local git inputs)
	@python3 -c '\
	import json; \
	lock = json.load(open("flake.lock")); \
	nodes = lock["nodes"]; \
	[print(n) for n, k in nodes["root"]["inputs"].items() \
	 if nodes.get(k if isinstance(k, str) else n, {}).get("locked", {}).get("type") == "git" \
	 and "file://" in nodes.get(k if isinstance(k, str) else n, {}).get("locked", {}).get("url", "")]' \
	| while IFS= read -r input; do \
	    nix flake update "$$input" 2>&1 | grep -v '^warning:' || true; \
	done

build:
	$(call announce,darwin-rebuild build --flake .#$(HOSTNAME))
	@sudo darwin-rebuild build --flake .#$(HOSTNAME)
	@rm -f result*

switch: lock-local
	$(call announce,darwin-rebuild switch --flake .#$(HOSTNAME))
	@sudo darwin-rebuild switch --flake .#$(HOSTNAME)
	@echo "Darwin generation: $$(sudo darwin-rebuild --list-generations | tail -1)"

update:
	$(call announce,nix flake update && brew update)
	nix flake update
	@if [[ -f /opt/homebrew/bin/brew ]]; then	\
	    eval "$(/opt/homebrew/bin/brew shellenv)";	\
	elif [[ -f /usr/local/bin/brew ]]; then		\
	    eval "$(/usr/local/bin/brew shellenv)";	\
	fi
	brew update

update-projects:
	$(call announce,nix flake update (in projects))
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)")
	@for project in "$${projects[@]}"; do	\
	    ( cd $(HOME)/$$project ;		\
	      echo "### $(HOME)/$$project" ;	\
	      nix flake update			\
	    );					\
	done

upgrade-tasks: switch travel-ready
	@if [[ -f /opt/homebrew/bin/brew ]]; then	\
	    eval "$(/opt/homebrew/bin/brew shellenv)";	\
	elif [[ -f /usr/local/bin/brew ]]; then		\
	    eval "$(/usr/local/bin/brew shellenv)";	\
	fi
	brew upgrade --greedy

upgrade: update upgrade-tasks

changes:
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)")
	@for project in "$${projects[@]}"; do	\
	    ( cd $(HOME)/$$project ;		\
	      echo "### $(HOME)/$$project" ;	\
	      changes				\
	    );					\
	done
	echo "### ~/.config/pushme"
	(cd ~/.config/pushme ; changes)
	echo "### ~/.emacs.d"
	(cd ~/.emacs.d ; changes)
	echo "### ~/src/nix"
	(cd ~/src/nix ; changes)
	echo "### ~/src/scripts"
	(cd ~/src/scripts ; changes)
	echo "### ~/doc"
	(cd ~/doc ; changes)
	echo "### ~/org"
	(cd ~/org ; changes)

########################################################################

copy:
	$(call announce,copy)
	@for host in $(REMOTES); do						\
	    nix copy --to "ssh-ng://$$host"					\
	        $(HOME)/.local/state/nix/profiles/profile;			\
	    readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)")	\
	    for project in "$${projects[@]}"; do				\
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

format:
	$(call announce,nixfmt)
	find . -name '*.nix' -not -path './result/*' | xargs nixfmt

travel-ready:
	$(call announce,travel-ready)
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)")
	@for project in "$${projects[@]}"; do				\
	    echo "Updating direnv on $(HOSTNAME) for ~/$$project";	\
	    (cd ~/$$project &&						\
             rm -f .envrc .envrc.cache;					\
             clean;							\
             if [[ $(HOSTNAME) == hera ]]; then				\
	         $(NIX_CONF)/bin/de;					\
             elif [[ $(HOSTNAME) == clio ]]; then			\
	         $(NIX_CONF)/bin/de;					\
             else							\
	         unset BUILDER;						\
	         $(NIX_CONF)/bin/de;					\
	     fi);							\
	done

.ONESHELL:
