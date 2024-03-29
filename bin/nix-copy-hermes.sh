#!/usr/bin/env bash

# u sign

nix copy --to "ssh-ng://hermes" ~/.local/state/nix/profiles/profile

for project in $(grep "^[^#]" ~/.config/projects)
do
    echo $project
    ( cd $project ; \
      if [[ -f .envrc.cache ]]; then \
          source <(direnv apply_dump .envrc.cache) ; \
          if [[ -n "$buildInputs" ]]; then \
              eval nix copy --to ssh-ng://hermes $buildInputs; \
          fi; \
      fi \
    )
done
