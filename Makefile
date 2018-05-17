REMOTE = vulcan
CACHE  = /Volumes/slim/Cache
ROOTS  = /nix/var/nix/gcroots/per-user/johnw/shells

SHELLS = $(HOME)/src/async-pool							\
	 $(shell find $(HOME)/bae/ $(HOME)/src/					\
		        \( -path $(HOME)/src/nix/nixpkgs -prune \)		\
		     -o \( -path $(HOME)/src/notes -prune \)			\
		     -o -name default.nix -print0				\
		   | parallel -0 'grep -q developPackage {} && echo {//}')

LOCALS = $(shell find $(HOME)/bae $(HOME)/src -name dir-locals.nix		\
	              ! -path $(HOME)/src/reflex-platform/dir-locals.nix)

PENVS = emacs26Env	\
	coq87Env	\
	ghc82Env	\
	ledgerPy3Env

ENVS =  emacsHEADEnv	\
	emacs26Env	\
	emacs26DebugEnv	\
	emacs25Env	\
	coqHEADEnv	\
	coq88Env	\
	coq87Env	\
	coq86Env	\
	coq85Env	\
	coq84Env	\
	ghc84Env	\
	ghc82ProfEnv	\
	ghc82Env	\
	ghc80Env	\
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
	nix build -f ~/src/nix/home-manager/home-manager/home-manager.nix \
		  --argstr confPath "$(HOME_MANAGER_CONFIG)" \
		  --argstr confAttr "" activationPackage \
		  --keep-going
	@rm result

shells:
	-find ~/bae/ ~/src/ -name .hdevtools.sock -delete
	for i in $(SHELLS); do							\
	    (cd $$i &&								\
	     echo "Building shell for $$i" &&					\
	     shell -k -Q -j4 --command true &&					\
	     (if [[ -f default.nix ]]; then					\
	          nix-instantiate --add-root $(ROOTS)/$$(basename $$i)-shell	\
	                          default.nix;					\
	      fi));								\
	done
# (cd $(HOME)/src/hnix &&							\
#  echo "Building ghc80 shell for hnix" &&				\
#  shell -k -Q -j4 --argstr compiler ghc802 --command true &&		\
#  nix-instantiate --add-root $(ROOTS)/$$(basename $$i)-shell-ghc80	\
#                  default.nix)
# (cd $(HOME)/src/hnix &&							\
#  echo "Building ghc84 shell for hnix" &&				\
#  shell -k -Q -j4 --argstr compiler ghc842 --command true &&		\
#  nix-instantiate --add-root $(ROOTS)/$$(basename $$i)-shell-ghc84	\
#                  default.nix)

locals:
	for i in $(LOCALS); do						\
	    (echo "Building dir-locals.el for $$i" &&			\
	     nix-build -k -Q -j4 $$i &&					\
	     nix-instantiate --add-root					\
	         $(ROOTS)/$$(basename $$(dirname $$i))-locals $$i);	\
	done

env-all:
	for i in $(ENVS); do \
	    nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.$$i ; \
	done
	@echo "Nix generation:    $$(nix-env --list-generations | tail -1)"

env-all-build:
	for i in $(ENVS); do \
	    echo Building $$i; \
	    nix build --keep-going darwin.pkgs.$$i ; \
	done
	@rm result

env:
	for i in $(PENVS); do \
	    echo Updating $$i; \
	    nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.$$i ; \
	done

env-build:
	for i in $(PENVS); do \
	    echo Building $$i; \
	    nix build --keep-going darwin.pkgs.$$i ; \
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
	git --git-dir=darwin/.git push --mirror jwiegley
	git --git-dir=home-manager/.git push --mirror jwiegley

working: tag-working mirror

update: tag-before pull build-all switch env-all \
	shells locals working cache copy

copy:
	nix copy --all --keep-going --to ssh://$(REMOTE)

cache:
	test -d $(CACHE) &&				\
	(find /nix/store -maxdepth 1 -type f		\
	    \( -name '*.dmg' -o				\
	       -name '*.zip' -o				\
	       -name '*.pkg' -o				\
	       -name '*.el'  -o				\
	       -name '*.7z'  -o				\
	       -name '*gz'   -o				\
	       -name '*xz'   -o				\
	       -name '*bz2'  -o				\
	       -name '*.tar' \) -print0			\
	    | parallel -0 nix copy --to file://$(CACHE))

gc:
	find $(HOME)				\
	    \( -name dist -type d -o		\
	       -name result -type l \) -print0	\
	    | parallel -0 /bin/rm -fr {}
	nix-collect-garbage --delete-older-than 14d

gc-all: gc
	nix-collect-garbage -d

### Makefile ends here
