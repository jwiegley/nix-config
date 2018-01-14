all: switch

darwin:
	darwin-rebuild switch -Q

darwin-build:
	nix build darwin.system

home:
	home-manager switch

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
	nix-env -f '<darwin>' -u --leq -Q -j4 -k -A pkgs \
	    || nix-env -f '<darwin>' -u --leq -Q -A pkgs

env:
	nix-env -f '<darwin>' -u --leq -Q -j4 -k -A pkgs.emacs26Env
	nix-env -f '<darwin>' -u --leq -Q -j4 -k -A pkgs.coq87Env
	nix-env -f '<darwin>' -u --leq -Q -j4 -k -A pkgs.ghc82Env
	nix-env -f '<darwin>' -u --leq -Q -j4 -k -A pkgs.ledgerPy3Env

build: darwin-build home-build env

build-all: darwin-build home-build env-all

switch: darwin home

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

update: tag-before pull build switch tag-working mirror copy update-remote

gc:
	find ~ \( -name dist -type d -o -name result -type l \) -print0 \
	    | parallel -0 /bin/rm -fr {}
	nix-garbage-collect --delete-older-than 14d
