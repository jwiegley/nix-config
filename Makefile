REMOTE = vulcan
CACHE  = /Volumes/slim/Cache

SHELLS = bae/micromht-fiat-deliverable/atif-fiat \
	 bae/concerto/solver

all: switch env-all

switch: darwin-switch home-switch

darwin-switch:
	darwin-rebuild switch -Q
	@echo "Darwin generation: $$(darwin-rebuild --list-generations | tail -1)"

darwin-build:
	nix build darwin.system
	rm result

home-switch:
	home-manager switch
	@echo "Home generation:   $$(home-manager generations | head -1)"

home-build:
	nix build -f ~/src/nix/home-manager/home-manager/home-manager.nix \
		  --argstr confPath "$(HOME_MANAGER_CONFIG)" \
		  --argstr confAttr "" activationPackage
	rm result

shells:
	for i in $(SHELLS); do \
	    (cd $(HOME)/$$i && nix-shell --command true); \
	done

env-all:
	nix-env -f '<darwin>' -u --leq -Q -k -A pkgs \
	    || nix-env -f '<darwin>' -u --leq -Q -A pkgs
	@echo "Nix generation:    $$(nix-env --list-generations | tail -1)"

env-all-build:
	nix build darwin.pkgs.emacs25Env
	nix build darwin.pkgs.emacs26Env
	nix build darwin.pkgs.emacs26DebugEnv
	nix build darwin.pkgs.emacsHEADEnv
	nix build darwin.pkgs.coq84Env
	nix build darwin.pkgs.coq85Env
	nix build darwin.pkgs.coq86Env
	nix build darwin.pkgs.coq87Env
	nix build darwin.pkgs.coqHEADEnv
	nix build darwin.pkgs.ghc80Env
	nix build darwin.pkgs.ghc82Env
	nix build darwin.pkgs.ghc82ProfEnv
	nix build darwin.pkgs.ledgerPy2Env
	nix build darwin.pkgs.ledgerPy3Env
	rm result

env:
	nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.emacs26Env
	nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.coq87Env
	nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.ghc82Env
	nix-env -f '<darwin>' -u --leq -Q -k -A pkgs.ledgerPy3Env

env-build:
	nix build darwin.pkgs.emacs26Env
	nix build darwin.pkgs.coq87Env
	nix build darwin.pkgs.ghc82Env
	nix build darwin.pkgs.ledgerPy3Env
	rm result

build: darwin-build home-build env-build

build-all: darwin-build home-build env-all-build

pull:
	(cd nixpkgs      && git pull --rebase)
	(cd darwin       && git pull --rebase)
	(cd home-manager && git pull --rebase)

tag-before:
	git --git-dir=nixpkgs/.git branch -f before-update HEAD

tag-working:
	git --git-dir=nixpkgs/.git branch -f last-known-good before-update
	git --git-dir=nixpkgs/.git branch -D before-update

mirror:
	git --git-dir=nixpkgs/.git push jwiegley -f unstable:unstable
	git --git-dir=darwin/.git push --mirror jwiegley
	git --git-dir=home-manager/.git push --mirror jwiegley

working: tag-working mirror

update: tag-before pull build-all switch env-all shells cache working

copy:
	nix copy --to ssh://$(REMOTE)			\
	    $(shell readlink -f ~/.nix-profile)		\
	    $(shell readlink -f /run/current-system)

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
