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
	nix-env -f '<nixpkgs>' -u --leq -Q -j4 -k || nix-env -f '<nixpkgs>' -u --leq -Q

mirror:
	git --git-dir=$(HOME)/oss/nixpkgs/.git push --mirror jwiegley
	git --git-dir=$(HOME)/oss/darwin/.git push --mirror jwiegley
	git --git-dir=$(HOME)/oss/home-manager/.git push --mirror jwiegley

copy:
	nix copy --to ssh://hermes $(shell readlink -f ~/.nix-profile)      \
	                           $(shell readlink -f /run/current-system)

update: tag-before pull env switch tag-working mirror copy
