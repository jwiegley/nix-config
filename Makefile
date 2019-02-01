HOSTNAME = vulcan
REMOTE	 = hermes
CACHE	 = /Users/johnw/tank/Cache
ROOTS	 = /nix/var/nix/gcroots/per-user/johnw/shells
ENVS     = emacsHEADEnv emacs26Env
NIX_CONF = $(HOME)/src/nix
PROJS    = $(shell find $(HOME)/dfinity $(HOME)/src -name .envrc -type f -printf '%h ')

all: switch env

NIXPATH = $(NIX_PATH):localconfig=$(NIX_CONF)/config/$(HOSTNAME).nix

darwin-build: config/darwin.nix
	NIX_PATH=$(NIXPATH) nix build --keep-going darwin.system
	@rm result

darwin-switch: darwin-build
	NIX_PATH=$(NIXPATH) darwin-rebuild switch -Q
	@echo "Darwin generation: $$(darwin-rebuild --list-generations | tail -1)"

home-build: config/home.nix
	NIX_PATH=$(NIXPATH)							\
	nix build -f $(NIX_CONF)/home-manager/home-manager/home-manager.nix	\
	    --argstr confPath "$(HOME_MANAGER_CONFIG)"				\
	    --argstr confAttr "" activationPackage				\
	    --keep-going
	@rm result

home-switch: home-build
	NIX_PATH=$(NIXPATH) home-manager switch
	@echo "Home generation: $$(home-manager generations | head -1)"

switch: darwin-switch home-switch

projs:
	@for i in $(PROJS); do \
	    echo "proj: $$i"; \
	done

shells:
	for i in $(PROJS); do				\
	    cd $$i;					\
	    echo;					\
	    echo Pre-building shell env for $$i;	\
	    echo;					\
	    NIX_PATH=$(NIXPATH) testit --make;		\
	    rm -f result;				\
	done

env-build: config/darwin.nix
	NIX_PATH=$(NIXPATH) nix build --keep-going darwin.pkgs.allEnvs
	@rm result

env:
	for i in $(ENVS); do					\
	    echo Updating $$i;					\
	    NIX_PATH=$(NIXPATH)					\
	    nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.$$i ;	\
	done
	@echo "Nix generation: $$(nix-env --list-generations | tail -1)"

build: darwin-build home-build env-build

pull:
	(cd darwin       && git pull --rebase)
	(cd home-manager && git pull --rebase)
	(cd nixpkgs      && git pull --rebase)

tag-before:
	git --git-dir=nixpkgs/.git branch -f before-update HEAD

tag-working:
	git --git-dir=nixpkgs/.git branch -f last-known-good before-update
	git --git-dir=nixpkgs/.git branch -D before-update
	git --git-dir=nixpkgs/.git tag -f \
	    known-good-$(shell git --git-dir=nixpkgs/.git show -s --format=%cd --date=format:%Y%m%d_%H%M%S last-known-good) \
	    last-known-good

mirror:
	git --git-dir=nixpkgs/.git push github -f master:master
	git --git-dir=nixpkgs/.git push github -f unstable:unstable
	git --git-dir=nixpkgs/.git push github -f last-known-good:last-known-good
	git --git-dir=nixpkgs/.git push -f --tags github
	git --git-dir=darwin/.git push --mirror jwiegley
	git --git-dir=home-manager/.git push --mirror jwiegley

working: tag-working mirror

update: tag-before pull build switch env working cache

copy-all: copy
	make -C $(NIX_CONF) NIX_CONF=$(NIX_CONF) REMOTE=fin copy

check:
	nix-store --verify --repair --check-contents

check-all: check
	ssh hermes 'make -C $(NIX_CONF) NIX_CONF=$(NIX_CONF) check'
	ssh fin    'make -C $(NIX_CONF) NIX_CONF=$(NIX_CONF) check'

size:
	sudo du --si -shx /nix/store

copy:
	push -f src,dfinity $(REMOTE)
	nix copy --keep-going --to ssh-ng://$(REMOTE)		\
	    $(shell readlink -f ~/.nix-profile)			\
	    $(shell readlink -f /run/current-system)		\
	    $(shell find $(PROJS) -path '*/.direnv/default'	\
		| while read dir; do				\
		    ls $$dir/ | while read file ; do		\
	              readlink $$dir/$$file;			\
	            done ;					\
	          done						\
	        | sort						\
		| uniq)
	ssh $(REMOTE) 'make -C $(NIX_CONF) NIX_CONF=$(NIX_CONF) HOSTNAME=$(REMOTE) build all'

cache: check
	-test -d $(CACHE) &&					\
	(find /nix/store -maxdepth 1 -type f			\
	    \( -name '*.dmg' -o					\
	       -name '*.zip' -o					\
	       -name '*.pkg' -o					\
	       -name '*.el'  -o					\
	       -name '*.7z'  -o					\
	       -name '*gz'   -o					\
	       -name '*xz'   -o					\
	       -name '*bz2'  -o					\
	       -name '*.tar' \) -print0				\
	    | parallel -0 nix copy --to file://$(CACHE))

remove-build-products:
	find $(HOME)/dfinity $(HOME)/Documents $(HOME)/src	\
	    \( -name 'dist' -type d -o				\
	       -name 'dist-newstyle' -type d -o			\
	       -name '.direnv' -type d -o			\
	       -name '.ghc.*' -o				\
	       -name 'cabal.project.local*' -type f -o		\
	       -name 'result*' -type l \) -print0		\
	    | xargs -P4 -0 /bin/rm -fr

gc:
	nix-collect-garbage --delete-older-than 14d

gc-all: remove-build-products
	sudo nix-env --delete-generations \
	    $(shell sudo nix-env --list-generations | field 1 | head -n -1)
	sudo nix-env -p /nix/var/nix/profiles/system --delete-generations \
	    $(shell sudo nix-env -p /nix/var/nix/profiles/system --list-generations | field 1 | head -n -1)
	nix-collect-garbage -d

fullclean: gc-all check
	ssh hermes 'make -C $(NIX_CONF) NIX_CONF=$(NIX_CONF) gc-all check'
	ssh fin    'make -C $(NIX_CONF) NIX_CONF=$(NIX_CONF) gc-all check'
