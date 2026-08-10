HOSTNAME   ?= $(shell myhost)
REMOTES	   = clio
GIT_REMOTE = jwiegley
MAX_AGE	   = 28
NIX_CONF   = $(HOME)/src/nix
SYSTEM     ?= $(shell nix eval --impure --raw --expr builtins.currentSystem)

.DEFAULT_GOAL := help
NIXOPTS	   =
PROJECTS   = $(HOME)/.config/projects

ifneq ($(BUILDER),)
NIXOPTS	  := $(NIXOPTS) --option builders 'ssh://$(BUILDER)'
endif

.PHONY: help all verify-inputs lock-local require-darwin-host build switch update update-projects upgrade-tasks upgrade \
	changes copy check sizes clean purge sign travel-ready test expensive tools repl format lint

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

help:
	@printf '%s\n' \
	  'Usage: make TARGET' \
	  '' \
	  'Non-mutating targets:' \
	  '  help             Show this help (default)' \
	  '  build            Build the current Darwin system without switching' \
	  '  expensive        Run the low-frequency exhaustive assurance tier' \
	  '  test             Build the core repository contracts' \
	  '  verify-inputs    Check local flake inputs for NAR hazards' \
	  '' \
	  'Mutating targets (explicit only):' \
	  '  format           Rewrite tracked Nix and shell sources' \
	  '  lint             Run every quality suite (test/bin/quality)' \
	  '  switch           Re-lock local inputs and switch nix-darwin' \
	  '  update           Update all locks/pins, switch, commit, and push' \
	  '  upgrade          Update, switch, and run upgrade tasks' \
	  '  clean / purge    Delete old Nix generations and store paths'

test:
	test/bin/quality --python-tier full python-test
	nix build --no-link \
	  .#checks.$(SYSTEM).agent-resources \
	  .#checks.$(SYSTEM).agent-wrappers \
	  .#checks.$(SYSTEM).ai-catalog-transport \
	  .#checks.$(SYSTEM).pi-extension-tests \
	  .#checks.$(SYSTEM).pi-gallery \
	  .#checks.$(SYSTEM).pi-fleet-theme

expensive:
	test/bin/quality --tier expensive
	nix build --no-link \
	  .#checks.$(SYSTEM).agent-resources \
	  .#checks.$(SYSTEM).agent-wrappers \
	  .#checks.$(SYSTEM).ai-catalog-transport \
	  .#checks.$(SYSTEM).pi-extension-tests \
	  .#checks.$(SYSTEM).pi-gallery \
	  .#checks.$(SYSTEM).pi-fleet-theme
	./build system

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

# Validate HOSTNAME only where a Darwin configuration consumes it, so
# host-independent targets (test, lint, help) stay runnable on any machine.
require-darwin-host:
	@case "$(HOSTNAME)" in \
	hera | clio) ;; \
	*) \
	    echo "Makefile: HOSTNAME '$(HOSTNAME)' is not a Darwin configuration; invoke as \`make HOSTNAME=hera|clio ...\`" >&2; \
	    exit 1 ;; \
	esac

repl: require-darwin-host
	nix --extra-experimental-features repl-flake \
	    repl .#darwinConfigurations.$(HOSTNAME).pkgs

verify-inputs:
	$(call announce,Verifying local git inputs for NAR hash safety)
	@errfile=$$(mktemp); \
	python3 bin/lib/local-git-inputs.py repos \
	| while IFS=$$'\t' read -r has_submodules repo; do \
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
	    if [ -n "$$gitlinks" ] && [ "$$has_submodules" != "1" ]; then \
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
	@if inputs=$$(python3 bin/lib/local-git-inputs.py names); then \
	    :; \
	else \
	    exit $$?; \
	fi; \
	if [ -n "$$inputs" ]; then \
	    printf '%s\n' "$$inputs" | while IFS= read -r input; do \
	    if output=$$(nix flake update "$$input" 2>&1); then \
	        if [ -n "$$output" ]; then \
	            printf '%s\n' "$$output" | grep -v '^warning:' || true; \
	        fi; \
	    else \
	        status=$$?; \
	        printf '%s\n' "$$output" >&2; \
	        exit "$$status"; \
	    fi; \
	    done; \
	fi

build: require-darwin-host
	$(call announce,darwin-rebuild build --flake .#$(HOSTNAME))
	@sudo darwin-rebuild build --flake .#$(HOSTNAME) $(NIXOPTS)
	@rm -f result

switch: require-darwin-host lock-local
	$(call announce,darwin-rebuild switch --flake .#$(HOSTNAME))
	@sudo darwin-rebuild switch --flake .#$(HOSTNAME) $(NIXOPTS)
	@echo "Darwin generation: $$(sudo darwin-rebuild --list-generations | tail -1)"

update:
	$(call announce,bin/update --all-inputs --pull --commit --switch --push)
	bin/update --all-inputs --pull --commit --switch --push

update-projects:
	$(call announce,nix flake update (in projects))
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)"); \
	for project in "$${projects[@]}"; do	\
	    ( cd $(HOME)/$$project ;		\
	      echo "### $(HOME)/$$project" ;	\
	      nix flake update			\
	    );					\
	done

upgrade-tasks: travel-ready
	@brew=$$(command -v brew || true);				\
	[[ -x $$brew ]] || brew=/opt/homebrew/bin/brew;			\
	[[ -x $$brew ]] || brew=/usr/local/bin/brew;			\
	[[ -x $$brew ]] || { echo 'upgrade-tasks: no brew found' >&2; exit 1; }; \
	eval "$$("$$brew" shellenv)";					\
	brew upgrade --greedy --yes

upgrade: update upgrade-tasks

changes:
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)"); \
	for project in "$${projects[@]}"; do	\
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
	    readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)");	\
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

scour:
	rm -fr $(HOME)/Library/Caches/pip
	rm -fr $(HOME)/.cache/bun
	rm -fr $(HOME)/.cache/cabal
	rm -fr $(HOME)/.cache/cargo
	rm -fr $(HOME)/.cache/ccache
	rm -fr $(HOME)/.cache/ghcide
	rm -fr $(HOME)/.cache/hie-bios
	rm -fr $(HOME)/.cache/nix
	rm -fr $(HOME)/.cache/npm
	rm -fr $(HOME)/.cache/pnpm
	rm -fr $(HOME)/.cache/rustup
	rm -fr $(HOME)/.cache/swiftpm
	rm -fr $(HOME)/.cache/uv
	rm -fr $(HOME)/.cache/.bun

purge: scour
	$(call delete-generations-all,1)
	nix-collect-garbage --delete-old
	sudo nix-collect-garbage --delete-old

sign:
	$(call announce,nix store sign -k "<key>" --all)
	@nix store sign -k $(HOME)/.config/gnupg/nix-signing-key.sec --all

# Delegate both rewrite suites to the single quality authority; do not duplicate
# formatter discovery here.
format:
	$(call announce,quality --fix)
	test/bin/quality --fix nix-format shell-format

lint:
	$(call announce,quality)
	test/bin/quality

travel-ready:
	$(call announce,travel-ready)
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)"); \
	for project in "$${projects[@]}"; do				\
	    echo "Updating direnv on $(HOSTNAME) for ~/$$project";	\
	    (cd ~/$$project &&						\
             rm -f .envrc .envrc.cache;					\
             clean;							\
             case "$(HOSTNAME)" in					\
             hera | clio) ;;						\
             *) unset BUILDER ;;					\
             esac;							\
	     $(NIX_CONF)/bin/de);					\
	done
