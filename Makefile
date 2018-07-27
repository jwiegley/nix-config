REMOTE = vulcan
CACHE  = /Volumes/tank/Cache
ROOTS  = /nix/var/nix/gcroots/per-user/johnw/shells

PROJS = src/async-pool							\
	src/bindings-DSL						\
	src/c2hsc							\
	src/git-all							\
	src/hierarchy							\
	src/hnix							\
	src/hours							\
	src/logging							\
	src/monad-extras						\
	src/numbers							\
	src/parsec-free							\
	src/pipes-async							\
	src/pipes-files							\
	src/pushme							\
	src/recursors							\
	src/refine-freer						\
	src/runmany							\
	src/sitebuilder							\
	src/sizes							\
	src/una								\
	src/z3-generate-api

PENVS = emacs26Env	\
	coq87Env	\
	ghc82Env	\
	ledgerPy3Env

ENVS =  emacsHEADEnv	\
	emacs26Env	\
	emacs26DebugEnv	\
	coqHEADEnv	\
	coq88Env	\
	coq87Env	\
	coq86Env	\
	coq85Env	\
	ghc84Env	\
	ghc82Env	\
	ledgerPy2Env	\
	ledgerPy3Env

all: switch env-all shells

switch: darwin-switch home-switch

darwin-switch:
	darwin-rebuild switch -Q
	@echo "Darwin generation: $$(darwin-rebuild --list-generations | tail -1)"

darwin-build:
	nix build --keep-going darwin.system
	@rm result

home-switch:
	home-manager switch
	@echo "Home generation:   $$(home-manager generations | head -1)"

home-build:
	nix build -f $(NIX_CONF)/home-manager/home-manager/home-manager.nix	\
	    --argstr confPath "$(HOME_MANAGER_CONFIG)"				\
	    --argstr confAttr "" activationPackage				\
	    --keep-going
	@rm result

shells:
	-find ~/bae/ ~/src/ -name .hdevtools.sock -delete
	for i in $(PROJS); do				\
	    cd $(HOME)/$$i;				\
	    echo Pre-building shell env for $$i;	\
	    testit --make;				\
	    rm -f result;				\
	done

env-all:
	for i in $(ENVS); do					\
	    echo Updating $$i;					\
	    nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.$$i ;	\
	done
	@echo "Nix generation:    $$(nix-env --list-generations | tail -1)"

env-all-build:
	nix build --keep-going darwin.pkgs.allEnvs
	@rm result

env:
	for i in $(PENVS); do					\
	    echo Updating $$i;					\
	    nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.$$i ;	\
	done

env-build:
	for i in $(PENVS); do				\
	    echo Building $$i;				\
	    nix build --keep-going darwin.pkgs.$$i ;	\
	done
	@rm result

build: darwin-build home-build env-build

build-all: darwin-build home-build env-all-build

pull:
	(cd darwin       && git pull --rebase)
	(cd home-manager && git pull --rebase)
	(cd nixpkgs      && git pull --rebase)

tag-before:
	git --git-dir=nixpkgs/.git branch -f before-update HEAD

tag-working:
	git --git-dir=nixpkgs/.git branch -f last-known-good before-update
	git --git-dir=nixpkgs/.git branch -D before-update

mirror:
	git --git-dir=nixpkgs/.git push github -f unstable:unstable
	git --git-dir=nixpkgs/.git push github -f master:master
	git --git-dir=darwin/.git push --mirror jwiegley
	git --git-dir=home-manager/.git push --mirror jwiegley

working: tag-working mirror

update: tag-before pull build-all switch env-all shells working cache

copy:
	nix copy --all --keep-going --to ssh://$(REMOTE)

cache:
	test -d $(CACHE) &&					\
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
	find $(HOME)					\
	    \( -name 'dist' -type d -o			\
	       -name 'result' -type l -o		\
	       -name 'result-*' -type l \) -print0	\
	    | parallel -0 /bin/rm -fr {}

gc:
	nix-collect-garbage --delete-older-than 14d

gc-all: gc
	nix-collect-garbage -d

### Makefile ends here
