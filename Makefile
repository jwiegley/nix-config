all: switch

darwin-switch:
	darwin-rebuild switch -Q
	@echo "Darwin generation: $$(darwin-rebuild --list-generations | tail -1)"

darwin-build:
	nix build darwin.system

home-switch:
	home-manager switch
	@echo "Home generation:   $$(home-manager generations | head -1)"

home-build:
	nix build -f ~/src/nix/home-manager/home-manager/home-manager.nix \
		  --argstr confPath "$(HOME_MANAGER_CONFIG)" \
		  --argstr confAttr "" activationPackage

pull:
	(cd nixpkgs      && git pull --rebase)
	(cd darwin       && git pull --rebase)
	(cd home-manager && git pull --rebase)

tag-before:
	git --git-dir=nixpkgs/.git branch -f before-update HEAD

tag-working:
	git --git-dir=nixpkgs/.git branch -f last-known-good before-update
	git --git-dir=nixpkgs/.git branch -D before-update

env-all:
	nix-env -f '<darwin>' -u --leq -Q -k -A pkgs \
	    || nix-env -f '<darwin>' -u --leq -Q -A pkgs
	@echo "Nix generation:    $$(nix-env --list-generations | tail -1)"

env-all-build:
	-nix build darwin.pkgs.myBuildEnvs
	nix-build '<darwin>' -Q -k -A pkgs.myBuildEnvs

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

build: darwin-build home-build env-build

build-all: darwin-build home-build env-all-build

switch: darwin-switch home-switch

mirror:
	git --git-dir=nixpkgs/.git push --mirror jwiegley
	git --git-dir=darwin/.git push --mirror jwiegley
	git --git-dir=home-manager/.git push --mirror jwiegley

copy:
	nix copy --to ssh://hermes $(shell readlink -f ~/.nix-profile)      \
	                           $(shell readlink -f /run/current-system)

update-remote:
	push -f Projects,Contracts,home hermes
	ssh hermes '(cd ~/src/nix ; make switch env-all)'

hermes: copy update-remote

working: tag-working mirror copy update-remote

update: tag-before pull build-all switch env-all working

gc:
	find ~ \( -name dist -type d -o -name result -type l \) -print0 \
	    | parallel -0 /bin/rm -fr {}
	nix-garbage-collect --delete-older-than 14d
