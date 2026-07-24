{ lib, runCommand }:

let
  overlay = import ../ai/30-agent-deck.nix;

  result =
    (overlay { } {
      buildGoModule = _: throw "agent-deck used the default Go builder";
      buildGo126Module = args: args // { builder = "go-1.26"; };
      fetchFromGitHub = args: args;
      inherit lib;
      makeWrapper = "make-wrapper";
      tmux = "/nix/store/fixture-tmux";
      git = "/nix/store/fixture-git";
    }).agent-deck;
in
assert result.builder == "go-1.26";
assert result.pname == "agent-deck";
assert result.version == "1.10.10";
runCommand "agent-deck-go-compat" { } "touch $out"
