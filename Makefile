HOSTNAME   = vulcan
CACHE      = vulcan
BUILDER    = vulcan
REMOTES	   = hermes
GIT_REMOTE = jwiegley
MAX_AGE	   = 14

# Lazily evaluated variables; expensive to compute, but we only want it do it
# when first necessary.
GIT_DATE   = git --git-dir=nixpkgs/.git show -s --format=%cd --date=format:%Y%m%d_%H%M%S
LKG_DATE   = $(eval LKG_DATE := $(shell $(GIT_DATE) last-known-good))$(LKG_DATE)

ifeq ($(CACHE),)
NIXOPTS	   = --option build-use-substitutes false	\
	     --max-jobs 20				\
	     --cores 4					\
	     --keep-going				\
	     --option substituters ''
else
ifeq ($(HOSTNAME),$(CACHE))
# NIXOPTS	   =
NIXOPTS	   = --max-jobs 20				\
	     --cores 4					\
	     --keep-going
else
NIXOPTS	   = --option build-use-substitutes true	\
	     --option require-sigs false		\
	     --max-jobs 20				\
	     --cores 4					\
	     --keep-going				\
	     --option substituters 'ssh://$(CACHE)'
endif
endif

ifeq ($(BUILDER),)
NIXOPTS	  := $(NIXOPTS) --option builders ''
else
ifneq ($(HOSTNAME),$(BUILDER))
NIXOPTS	  := $(NIXOPTS) --option builders 'ssh://$(BUILDER)'
endif
endif

NIX_CONF  := $(HOME)/src/nix

# When building with the Makefile, rather than calling darwin-rebuild
# directly, we set the NIX_PATH to point at whatever is the latest pull of the
# various projects used to build this Nix configuration. See nix.nixPath in
# darwin.nix for the system definition of the NIX_PATH, which relies on
# whichever versions of the below were used to build that generation.
NIX_PATH   = localconfig=$(NIX_CONF)/config/$(HOSTNAME).nix
NIX_PATH  := $(NIX_PATH):nixpkgs=$(HOME)/src/nix/nixpkgs
NIX_PATH  := $(NIX_PATH):darwin=$(HOME)/src/nix/darwin
NIX_PATH  := $(NIX_PATH):darwin-config=$(HOME)/src/nix/config/darwin.nix
NIX_PATH  := $(NIX_PATH):home-manager=$(HOME)/src/nix/home-manager
NIX_PATH  := $(NIX_PATH):hm-config=$(HOME)/src/nix/config/home.nix
NIX_PATH  := $(NIX_PATH):ssh-config-file=$(HOME)/.ssh/config
NIX_PATH  := $(NIX_PATH):ssh-auth-sock=$(HOME)/.config/gnupg/S.gpg-agent.ssh

NIX	   = $(PRENIX) nix
NIX_BUILD  = $(PRENIX) nix-build
NIX_ENV	   = $(PRENIX) nix-env
NIX_STORE  = $(PRENIX) nix-store
NIX_GC	   = $(PRENIX) nix-collect-garbage

BUILD_ARGS = $(NIXOPTS) --keep-going
ifeq ($(REALBUILDPATH),true)
BUILD_PATH = $(eval BUILD_PATH :=					\
		$(shell echo NIX_PATH=$(NIX_PATH) nix-build $(BUILD_ARGS)))$(BUILD_PATH)
else
BUILD_PATH = /run/current-system
endif

PRENIX	  := PATH=$(BUILD_PATH)/sw/bin:$(PATH) NIX_PATH=$(NIX_PATH)

all: rebuild

%-all: %
	@for host in $(REMOTES); do						\
	    ssh $$host "CACHE=$(CACHE) NIX_CONF=$(NIX_CONF) u $$host $<";	\
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

build:
	$(call announce,nix build -f "<darwin>" system)
	@$(NIX) build $(BUILD_ARGS) -f "<darwin>" system
	@rm -f result*

# echo $(PRENIX) darwin-rebuild switch --cores 1 -j1
switch:
	$(call announce,darwin-rebuild switch)
	@$(PRENIX) darwin-rebuild switch --cores 1 -j1
	@echo "Darwin generation: $$($(PRENIX) darwin-rebuild --list-generations | tail -1)"

rebuild: build switch

pull:
	$(call announce,git pull)
	(cd nixpkgs	 && git pull --rebase)
	(cd darwin	 && git pull --rebase)
	(cd home-manager && git pull --rebase)

tag-before:
	$(call announce,git tag before-update)
	git --git-dir=nixpkgs/.git branch -f before-update HEAD

tag-working:
	$(call announce,git tag last-known-good)
	git --git-dir=nixpkgs/.git branch -f last-known-good before-update
	git --git-dir=nixpkgs/.git branch -D before-update
	git --git-dir=nixpkgs/.git tag -f known-good-$(LKG_DATE) last-known-good

mirror:
	$(call announce,git push)
	@for name in master unstable last-known-good; do	\
	    git --git-dir=nixpkgs/.git push $(GIT_REMOTE)	\
	        -f $${name}:$${name};				\
	done
	git --git-dir=nixpkgs/.git push -f --tags $(GIT_REMOTE)
	git --git-dir=darwin/.git push --mirror $(GIT_REMOTE)
	git --git-dir=home-manager/.git push --mirror $(GIT_REMOTE)

update: tag-before pull rebuild tag-working mirror

update-sync: update copy rebuild-all

########################################################################

copy-nix:
	$(call announce,nix copy)
	@for host in $(REMOTES); do				\
	    $(NIX) copy --keep-going --to ssh://$$host		\
		$(HOME)/.nix-profile $(BUILD_PATH);		\
	done

copy-src:
	$(call announce,pushme)
	@for host in $(REMOTES); do				\
	    push -f src,kadena $$host;				\
	done

direnv-dirs:
	@find $(HOME)/kadena					\
	      $(HOME)/src					\
	      $(HOME)/doc					\
	    \( -path '*/Containers' -prune \) -o		\
	    \( -path '*/.Trash' -prune \) -o			\
	    -path '*/.direnv/default' -type l -print

copy-direnv:
	$(call announce,nix copy (direnv))
	@find $(HOME)/kadena					\
	      $(HOME)/src					\
	      $(HOME)/doc					\
	    \( -path '*/Containers' -prune \) -o		\
	    \( -path '*/.Trash' -prune \) -o			\
	    -path '*/.direnv' -type d -print |			\
	    while read file ; do				\
	        for host in $(REMOTES); do			\
	            echo "nix copy: $$file -> $$host";		\
		    find $$file \!				\
			-name env.drv -name 'dep*'		\
			-type l -print0 |			\
		        $(PRENIX) xargs -0 nix copy		\
			    --keep-going --to ssh://$$host;	\
	        done;						\
	    done

copy: copy-nix copy-src copy-direnv

########################################################################

define delete-generations
	$(NIX_ENV) $(1) --delete-generations			\
	    $(shell $(NIX_ENV) $(1)				\
		--list-generations | field 1 | head -n -$(2))
endef

define delete-generations-all
	$(call delete-generations,,$(1))
	$(call delete-generations,-p /nix/var/nix/profiles/system,$(1))
endef

clean: gc check

fullclean: gc-old check

gc:
	$(call delete-generations-all,$(MAX_AGE))
	$(NIX_GC) --delete-older-than $(MAX_AGE)d

gc-old:
	$(call delete-generations-all,1)
	$(NIX_GC) --delete-old

check:
	$(call announce,nix-store --check-contents)
	$(NIX_STORE) --verify --repair --check-contents

sizes:
	df -H /nix 2>&1 | grep /dev

S3_CACHE = "s3://jw-nix-cache?region=us-west-001&endpoint=s3.us-west-001.backblazeb2.com"

sign-store:
	nix store sign -k ~/.config/gnupg/nix-signing-key.sec --all

cache-system:
	$(call announce,nix-copy system)
	nix copy --to $(S3_CACHE)					\
	    $$(readlink .nix-profile)					\
	    $$(readlink /var/run/current-system)

cache-sources:
	$(call announce,nix-copy sources)
	find /nix/store/ -maxdepth 1 \(					\
	       -name '*.xz'						\
	    -o -name '*.bz2'						\
	    -o -name '*.gz'						\
	    -o -name '*.dmg'						\
	    -o -name '*.zip'						\
	    -o -name '*.tar'						\
	     \) -type f -print0 |					\
	    xargs -0 nix copy --to $(S3_CACHE)

cache-envs:
	$(call announce,nix-copy envs)
	find $(HOME) -path '*/.direnv/default/dep*' -type l |		\
	    while read dir; do						\
	        echo $$dir ;						\
	        nix copy --to $(S3_CACHE) $${dir}/* ;			\
	    done

cache: sign-store cache-system cache-sources cache-envs

PROJECTS = $(HOME)/.config/projects

travel-ready:
	$(call announce,travel-ready)
	@readarray -t projects < <(egrep -v '^(#.+)?$$' "$(PROJECTS)")
	@for dir in "$${projects[@]}"; do				\
	    echo "Updating direnv for ~/$$dir";				\
	    (cd ~/$$dir; unset BUILDER; de)				\
	done

.ONESHELL:
