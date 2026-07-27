# overlays/30-misc-tools.nix
# Purpose: Miscellaneous utility tools (file management, shell, security)
# Dependencies: prev.myLib (from 00-lib.nix) for the single-binary jwiegley
#               packages; everything else uses prev directly.
# Packages: cmdperf, gogcli (bumped), hammer, linkdups, lipotell, sift, sshify, z
# Note: pass-git-helper, yamale removed (now in nixpkgs)
_final: prev:
let
  sources = import ../packages/source-catalog.nix "tools";
  # gogcli 0.34.0 requires the Go 1.26.5 security release, one patch ahead
  # of the Go compiler in the currently locked nixpkgs.
  go_1_26_5 = prev.buildPackages.go_1_26.overrideAttrs {
    version = sources."go-1.26.5".version;
    src =
      assert sources."go-1.26.5".source.fetcher == "fetchurl";
      prev.fetchurl sources."go-1.26.5".source.args;
  };
  buildGo1265Module = prev.buildGo126Module.override { go = go_1_26_5; };
in
{

  # cmdperf: command performance benchmarking (hyperfine-style). Not in
  # nixpkgs. Pure Go, upstream builds with CGO disabled; goreleaser's
  # default ldflags stamp main.version.
  cmdperf = prev.buildGoModule (finalAttrs: {
    pname = "cmdperf";
    version = sources.cmdperf.version;

    src =
      assert sources.cmdperf.source.fetcher == "fetchFromGitHub";
      prev.fetchFromGitHub sources.cmdperf.source.args;

    vendorHash = sources.cmdperf.hashes.vendorHash;

    subPackages = [ "cmd/cmdperf" ];

    env.CGO_ENABLED = 0;

    ldflags = [
      "-s"
      "-w"
      "-X main.version=${finalAttrs.version}"
    ];

    meta = {
      description = "Command performance benchmarking";
      homepage = "https://github.com/miklosn/cmdperf";
      license = prev.lib.licenses.mit;
      mainProgram = "cmdperf";
    };
  });

  # Bump gogcli ahead of nixpkgs (still at 0.11.0 under steipete/gogcli).
  # Upstream moved to openclaw/gogcli; Go module path is unchanged.
  gogcli = (prev.gogcli.override { buildGoModule = buildGo1265Module; }).overrideAttrs (
    finalAttrs: _oldAttrs: {
      version = sources.gogcli.version;
      src =
        assert sources.gogcli.source.fetcher == "fetchFromGitHub";
        prev.fetchFromGitHub sources.gogcli.source.args;
      vendorHash = sources.gogcli.hashes.vendorHash;
    }
  );

  # highlight 4.20 (pulled in by the latest nixpkgs bump) already includes
  # the shellscript crash fix (gitlab commit 2c0e9529) upstream, but nixpkgs
  # still lists shellscript-crash-fix.patch in `patches`. Applying it now
  # fails with "Reversed (or previously applied) patch detected", breaking
  # the build. Drop the redundant patch; remove this override once nixpkgs
  # stops carrying it.
  highlight = prev.highlight.overrideAttrs (
    _finalAttrs: oldAttrs: {
      patches = builtins.filter (p: !prev.lib.hasInfix "shellscript-crash-fix" (p.name or "")) (
        oldAttrs.patches or [ ]
      );
    }
  );

  hammer = prev.myLib.mkSimpleGitHubBinary {
    pname = "hammer";
    source = sources.hammer;
    description = "A tool for fixing broken symlinks";
  };

  linkdups = prev.myLib.mkSimpleGitHubBinary {
    pname = "linkdups";
    source = sources.linkdups;
    description = "A tool for hard-linking duplicate files";
  };

  lipotell = prev.myLib.mkSimpleGitHubBinary {
    pname = "lipotell";
    source = sources.lipotell;
    description = "A tool to find large files within a directory";
  };

  sift = prev.myLib.mkSimpleGitHubBinary {
    pname = "sift";
    source = sources.sift;
    description = "A tool for sifting apart large patch files";
  };

  sshify = prev.myLib.mkSimpleGitHubBinary {
    pname = "sshify";
    source = sources.sshify;
    description = "A tool for installing SSH authorized_key on remote servers";
  };

  # Track most-used directories based on frecency
  z =
    with prev;
    stdenv.mkDerivation rec {
      name = "z-${version}";
      version = sources.z.version;

      src =
        assert sources.z.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.z.source.args;

      phases = [
        "unpackPhase"
        "installPhase"
      ];

      installPhase = ''
        mkdir -p $out/share
        cp -p z.sh $out/share/z.sh
      '';

      meta = with prev.lib; {
        description = "Tracks your most used directories, based on 'frecency'.";
        homepage = "https://github.com/rupa/z";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.unix;
      };
    };

}
