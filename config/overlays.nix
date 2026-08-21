# Explicit overlay authority for Darwin and standalone Home Manager consumers.
{
  inputs,
  # No caller in this repository passes aiOverlay, but the andoria-08
  # shared-work consumer (~/src/andoria flake.nix) injects its own pinned
  # nix-config-ai overlay through it; removing the parameter hard-breaks
  # that fleet host's evaluation.
  aiOverlay ? null,
  vulcan-crt ? null,
}:

let
  darwinOnly =
    overlay: final: prev:
    if prev.stdenv.hostPlatform.isDarwin then overlay final prev else { };

  caOverlay = _final: prev: {
    ca-bundle-with-vulcan = prev.runCommand "ca-bundle-with-vulcan" { } ''
      mkdir -p $out/etc/ssl/certs
      cat ${prev.cacert}/etc/ssl/certs/ca-bundle.crt ${vulcan-crt}/vulcan-root-ca.crt \
        > $out/etc/ssl/certs/ca-bundle.crt
    '';
  };

  foundation = [
    (import ../overlays/00-lib.nix)
    (darwinOnly (import ../overlays/00-last-known-good.nix))
    (import ../overlays/10-coq.nix)
    (import ../overlays/10-eask-cli.nix)
    ((import ../overlays/10-emacs.nix) {
      hours = inputs.hours or null;
      emacsSrc = inputs.emacs-src or null;
    })
    (import ../overlays/15-python-fixes.nix)
    (darwinOnly (import ../overlays/15-darwin-fixes.nix))
  ];

  features = [
    (import ../overlays/30-cpx.nix)
    ((import ../overlays/30-data-tools.nix) { dirscan = inputs.dirscan or null; })
    ((import ../overlays/30-git-tools.nix) {
      gitScripts = inputs.git-scripts or null;
    })
    ((import ../overlays/30-ledger.nix) { ledger = inputs.ledger or null; })
    (import ../overlays/30-markless.nix)
    (import ../overlays/30-misc-tools.nix)
    ((import ../overlays/30-stock-trader-mcp.nix) {
      stockTrader = inputs.stock-trader or null;
    })
    ((import ../overlays/30-text-tools.nix) { org2tc = inputs.org2tc or null; })
    ((import ../overlays/30-user-scripts.nix) { scripts = inputs.scripts or null; })
  ];

  ai = if aiOverlay == null then import ../overlays/ai { inherit inputs; } else [ aiOverlay ];
in
foundation ++ (if vulcan-crt == null then [ ] else [ caOverlay ]) ++ features ++ ai
