/goal Run daily updates for repositories forks and Nix software

I want to run through a daily upgrade of the entire system. The involves three things:

1. Update all of the Git repositories that we track
2. Update all the forked projects that we maintain here
3. Update all of the software versions we track through Nix.

## Update sources

To update all of the Git projects that we track on this system, run:

```
update ~/doc ~/src ~/Models ~/work
```

Make sure to notice and resolve any issues that arise.

## Update forks

In order to update our forks, we must:

1. Change to the directory where we have cloned and maintain our fork
2. Figure out the latest release version of the upstream software
3. Use `git fetch --all` to download all commits and tags.
4. Rebase our \`main\` with the latest upstream release tag.
5. Resolve any conflicts that arise, so that we continue to port our own changes forward onto the newest release — or drop them if they are no longer relevant.
6. Commit our resolutions in the correct respective commits.
7. Force-push to update our fork on GitHub.

These are the forks that we maintain:

- `~/src/fork/autoagent`
- `~/src/fork/agent-deck`
- `~/src/fork/CLIProxyAPI`
- `~/src/fork/codex`
- `~/src/fork/omlx`
- `~/src/fork/pal-mcp-server`
- `~/src/fork/pi`
- `~/src/fork/vibeproxy`

Make sure to notice and resolve any issues that arise with either resolving rebase conflicts, building the updated version of the software, or while running its full validation tests.

## Update software through Nix

Finally, we update Nix itself by changing to the `~/src/nix` directory and running:

```
bin/update --all-inputs
./build system
make switch
```

Resolve any issues while updating or building. If all succeeds, then the system is fully updated! Make sure that any changes through the process have been properly committed, push, updated, and activated on Hera.
