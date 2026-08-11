HOSTNAME   ?= $(shell myhost)
REMOTES	   = clio
GIT_REMOTE = jwiegley
NIX_CONF   = $(HOME)/src/nix
SYSTEM     ?= $(shell nix eval --impure --raw --expr builtins.currentSystem)
.DEFAULT_GOAL := help
NIXOPTS	   =
PROJECTS   = $(HOME)/.config/projects

ifneq ($(BUILDER),)
NIXOPTS	  := $(NIXOPTS) --option builders 'ssh://$(BUILDER)'
endif

.PHONY: help all verify-inputs lock-local require-darwin-host build switch update update-projects upgrade-tasks upgrade \
	changes copy check repair-store sizes scour sign travel-ready test expensive tools repl format lint

# These maintenance recipes use Bash functions, strict mode, and arrays.
verify-inputs update-projects upgrade-tasks changes copy travel-ready: SHELL := bash

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

# Keep list input off stdin, and close its descriptor before invoking a callback.
define for-each-project
for_each_project() { \
	local callback="$$1" projects_file="$$2"; \
	local project project_dir command_status status=0; \
	if [[ ! -f "$$projects_file" || ! -r "$$projects_file" ]]; then \
	    printf 'Makefile: project list is not a readable file: %s\n' \
	        "$$projects_file" >&2; \
	    return 1; \
	fi; \
	if [[ -z "$${HOME:-}" ]]; then \
	    printf 'Makefile: HOME is not set\n' >&2; \
	    return 1; \
	fi; \
	if ! exec 9< "$$projects_file"; then \
	    printf 'Makefile: could not open project list: %s\n' "$$projects_file" >&2; \
	    return 1; \
	fi; \
	while IFS= read -r project <&9 || [[ -n "$$project" ]]; do \
	    [[ -n "$$project" && "$$project" != \#* ]] || continue; \
	    project_dir="$$HOME/$$project"; \
	    if [[ ! -d "$$project_dir" ]]; then \
	        printf 'Makefile: project directory not found: %s\n' "$$project_dir" >&2; \
	        status=1; \
	        continue; \
	    fi; \
	    (set -euo pipefail; cd "$$project_dir"; "$${callback}" "$$project_dir" "$$project") 9<&-; \
	    command_status=$$?; \
	    if ((command_status != 0)); then \
	        printf 'Makefile: project command failed (%s): %s\n' \
	            "$$command_status" "$$project_dir" >&2; \
	        status=1; \
	    fi; \
	done; \
	exec 9<&-; \
	return "$$status"; \
}; \
for_each_project "$(1)" "$(PROJECTS)"
endef

help:
	@printf '%s\n' \
	  'Usage: make TARGET' \
	  '' \
	  'Non-mutating targets:' \
	  '  help             Show this help (default)' \
	  '  build            Build the current Darwin system without switching' \
	  '  check            Verify every Nix store path without repairing it' \
	  '  expensive        Run the low-frequency exhaustive assurance tier' \
	  '  test             Build the core repository contracts' \
	  '  verify-inputs    Check local flake inputs for NAR hazards' \
	  '' \
	  'Mutating targets (explicit only):' \
	  '  format           Rewrite tracked Nix and shell sources' \
	  '  lint             Run every quality suite (test/bin/quality)' \
	  '  repair-store     Verify and repair every Nix store path' \
	  '  switch           Re-lock local inputs and switch nix-darwin' \
	  '  update           Update all locks/pins, switch, commit, and push' \
	  '  upgrade          Update, switch, and run upgrade tasks'

test:
	test/bin/quality --python-tier full python-test
	test/bin/check-manifest baseline root "$(SYSTEM)"

expensive:
	test/bin/quality --tier expensive
	test/bin/check-manifest closeout root "$(SYSTEM)"
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
	@inventory=$$(mktemp) || exit; \
	errfile=$$(mktemp) || { status=$$?; rm -f "$$inventory"; exit "$$status"; }; \
	trap 'rm -f "$$inventory" "$$errfile"' EXIT; \
	if python3 bin/lib/local-git-inputs.py repos >"$$inventory"; then \
	    :; \
	else \
	    exit $$?; \
	fi; \
	if ! python3 -c 'import sys; data = open(sys.argv[1], "rb").read(); sys.exit(b"\0" in data or bool(data and not data.endswith(b"\n")))' "$$inventory"; then \
	    echo "ERROR: invalid local git input inventory framing" >&2; \
	    exit 2; \
	fi; \
	records=(); \
	inventory_pattern=$$'^[01]\t/[^[:cntrl:]]+$$'; \
	while IFS= read -r row; do \
	    if [[ ! "$$row" =~ $$inventory_pattern ]]; then \
	        echo "ERROR: invalid local git input inventory" >&2; \
	        exit 2; \
	    fi; \
	    records+=( "$$row" ); \
	done <"$$inventory"; \
	for row in "$${records[@]}"; do \
	    IFS=$$'\t' read -r has_submodules repo <<<"$$row"; \
	    if files=$$(git -C "$$repo" ls-files -v); then \
	        :; \
	    else \
	        status=$$?; \
	        echo "ERROR: git ls-files -v failed for $$repo" >&2; \
	        exit "$$status"; \
	    fi; \
	    bad=$$(printf '%s\n' "$$files" | grep -E '^[shS] ' || true); \
	    if [ -n "$$bad" ]; then \
	        echo "ERROR: $$repo has skip-worktree/assume-unchanged files:" | tee -a "$$errfile"; \
	        echo "$$bad" | tee -a "$$errfile"; \
	        echo "Fix: git -C $$repo update-index --no-skip-worktree --no-assume-unchanged <files>" | tee -a "$$errfile"; \
	        echo "Then: git -C $$repo checkout -- <files>" | tee -a "$$errfile"; \
	    fi; \
	    if submodules=$$(git -C "$$repo" submodule status --recursive); then \
	        :; \
	    else \
	        status=$$?; \
	        echo "ERROR: git submodule status failed for $$repo" >&2; \
	        exit "$$status"; \
	    fi; \
	    uninit=$$(printf '%s\n' "$$submodules" | grep '^-' || true); \
	    if [ -n "$$uninit" ]; then \
	        echo "ERROR: $$repo has uninitialized submodules:" | tee -a "$$errfile"; \
	        echo "$$uninit" | tee -a "$$errfile"; \
	        echo "Fix: cd $$repo && git submodule update --init --recursive" | tee -a "$$errfile"; \
	    fi; \
	    if staged=$$(git -C "$$repo" ls-files --stage); then \
	        :; \
	    else \
	        status=$$?; \
	        echo "ERROR: git ls-files --stage failed for $$repo" >&2; \
	        exit "$$status"; \
	    fi; \
	    gitlinks=$$(printf '%s\n' "$$staged" | grep '^160000' || true); \
	    if [ -n "$$gitlinks" ] && [ "$$has_submodules" != "1" ]; then \
	        echo "ERROR: $$repo has gitlinks but its lock omits submodules=true:" | tee -a "$$errfile"; \
	        echo "$$gitlinks" | tee -a "$$errfile"; \
	        echo "Fix: remove the gitlinks or lock the input with submodules=true" | tee -a "$$errfile"; \
	    fi; \
	done; \
	if [ -s "$$errfile" ]; then \
	    echo ""; \
	    echo "NAR hash mismatches will occur until the above are fixed."; \
	    echo "See: nix flake update uses filesystem, darwin-rebuild uses git archive."; \
	    exit 1; \
	fi

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
	@update_project() { \
	    printf '### %s\n' "$$1"; \
	    nix flake update; \
	}; \
	$(call for-each-project,update_project)

upgrade-tasks: travel-ready
	@brew=$$(command -v brew || true);				\
	[[ -x $$brew ]] || brew=/opt/homebrew/bin/brew;			\
	[[ -x $$brew ]] || brew=/usr/local/bin/brew;			\
	[[ -x $$brew ]] || { echo 'upgrade-tasks: no brew found' >&2; exit 1; }; \
	eval "$$("$$brew" shellenv)";					\
	brew upgrade --greedy --yes

upgrade: update
	@$(MAKE) --no-print-directory upgrade-tasks

changes:
	@if [[ -z "$${HOME:-}" ]]; then \
	    printf 'Makefile: HOME is not set\n' >&2; \
	    exit 1; \
	fi; \
	changes_project() { \
	    printf '### %s\n' "$$1"; \
	    changes; \
	}; \
	status=0; \
	$(call for-each-project,changes_project); \
	command_status=$$?; \
	((command_status == 0)) || status=1; \
	for repo in .config/pushme .emacs.d src/nix src/scripts doc org; do \
	    printf '### ~/%s\n' "$$repo"; \
	    (cd "$$HOME/$$repo" && changes) || status=1; \
	done; \
	exit "$$status"

########################################################################

copy:
	$(call announce,copy)
	@copy_project() { \
	    local env_dump; \
	    local build_input store_name; \
	    local store_pattern='^/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-([A-Za-z0-9+._?=-]{1,211})$$'; \
	    local -a build_inputs=() input_line=(); \
	    printf '%s\n' "$$2"; \
	    if [[ -f .envrc.cache ]]; then \
	        if ! env_dump=$$(direnv apply_dump .envrc.cache); then \
	            printf 'Makefile: direnv apply_dump failed: %s\n' "$$1" >&2; \
	            return 1; \
	        fi; \
	        if ! source /dev/stdin <<<"$$env_dump"; then \
	            printf 'Makefile: invalid direnv environment dump: %s\n' "$$1" >&2; \
	            return 1; \
	        fi; \
	        while read -r -a input_line; do \
	            build_inputs+=( "$${input_line[@]}" ); \
	        done <<<"$${buildInputs:-}"; \
	        if (($${#build_inputs[@]} > 0)); then \
	            for build_input in "$${build_inputs[@]}"; do \
	                if [[ ! "$$build_input" =~ $$store_pattern ]]; then \
	                    printf 'Makefile: invalid cached build input: %s\n' "$$1" >&2; \
	                    return 1; \
	                fi; \
	                store_name=$${BASH_REMATCH[1]}; \
	                case "$$store_name" in \
	                . | .. | .-* | ..-*) \
	                    printf 'Makefile: invalid cached build input: %s\n' "$$1" >&2; \
	                    return 1 ;; \
	                esac; \
	            done; \
	            if ! nix copy --to "ssh-ng://$$host" "$${build_inputs[@]}"; then \
	                printf 'Makefile: nix copy failed: %s\n' "$$1" >&2; \
	                return 1; \
	            fi; \
	        fi; \
	    fi; \
	}; \
	status=0; \
	for host in $(REMOTES); do \
	    nix copy --to "ssh-ng://$$host" \
	        "$$HOME/.local/state/nix/profiles/profile"; \
	    command_status=$$?; \
	    ((command_status == 0)) || status=1; \
	    $(call for-each-project,copy_project); \
	    command_status=$$?; \
	    ((command_status == 0)) || status=1; \
	done; \
	exit "$$status"

########################################################################

check:
	$(call announce,nix store verify --no-trust --all)
	@nix store verify --no-trust --all

repair-store:
	$(call announce,nix store verify --no-trust --repair --all)
	@nix store verify --no-trust --repair --all

sizes:
	df -H /nix 2>&1 | grep /dev

scour:
	@case "$${HOME:-}" in \
	/*) ;; \
	*) printf 'Makefile: HOME must be an absolute path\n' >&2; exit 1 ;; \
	esac
	rm -fr -- "$${HOME}/Library/Caches/pip"
	rm -fr -- "$${HOME}/.cache/bun"
	rm -fr -- "$${HOME}/.cache/cabal"
	rm -fr -- "$${HOME}/.cache/cargo"
	rm -fr -- "$${HOME}/.cache/ccache"
	rm -fr -- "$${HOME}/.cache/ghcide"
	rm -fr -- "$${HOME}/.cache/hie-bios"
	rm -fr -- "$${HOME}/.cache/nix"
	rm -fr -- "$${HOME}/.cache/npm"
	rm -fr -- "$${HOME}/.cache/pnpm"
	rm -fr -- "$${HOME}/.cache/rustup"
	rm -fr -- "$${HOME}/.cache/swiftpm"
	rm -fr -- "$${HOME}/.cache/uv"
	rm -fr -- "$${HOME}/.cache/.bun"
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
	@travel_project() { \
	    printf 'Updating direnv on %s for ~/%s\n' "$(HOSTNAME)" "$$2"; \
	    rm -f .envrc .envrc.cache; \
	    clean; \
	    case "$(HOSTNAME)" in \
	    hera | clio) ;; \
	    *) unset BUILDER ;; \
	    esac; \
	    "$(NIX_CONF)/bin/de"; \
	}; \
	$(call for-each-project,travel_project)
