all: switch

darwin:
	darwin-rebuild switch

darwin-build:
	darwin-rebuild build

home:
	home-manager switch

home-build:
	home-manager build

switch: darwin home

build: darwin-build home-build

pull:
	(cd ~/oss/nixpkgs      && git pull --rebase)
	(cd ~/oss/darwin       && git pull --rebase)
	(cd ~/oss/home-manager && git pull --rebase)

tag-before:
	git --git-dir=$(HOME)/oss/nixpkgs/.git branch -f before-update HEAD

tag-working:
	git --git-dir=$(HOME)/oss/nixpkgs/.git branch -f last-known-good before-update
	git --git-dir=$(HOME)/oss/nixpkgs/.git branch -D before-update

env:
	nix-env -f '<darwin>' -u --leq -Q -j4 -k -A pkgs \
	    || nix-env -f '<darwin>' -u --leq -Q -A pkgs

mirror:
	git --git-dir=$(HOME)/oss/nixpkgs/.git push --mirror jwiegley
	git --git-dir=$(HOME)/oss/darwin/.git push --mirror jwiegley
	git --git-dir=$(HOME)/oss/home-manager/.git push --mirror jwiegley

copy:
	nix copy --to ssh://hermes $(shell readlink -f ~/.nix-profile)      \
	                           $(shell readlink -f /run/current-system)

update-remote:
	push -f Projects,Contracts,home hermes
	ssh hermes '(cd ~/src/nix ; make env switch)'

update: tag-before pull env switch tag-working mirror copy update-remote

gc:
	find ~ \( -name dist -type d -o -name result -type l \) -print0 \
	    | parallel -0 /bin/rm -fr {}
	nix-garbage-collect --delete-older-than 14d
