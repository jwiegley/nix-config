# overlays/30-misc-tools.nix
# Purpose: Miscellaneous utility tools (file management, shell, security)
# Dependencies: prev.myLib (from 00-lib.nix) for the single-binary jwiegley
#               packages; everything else uses prev directly.
# Packages: cmdperf, gogcli (bumped), hammer, linkdups, lipotell, sift, sshify, z
# Note: pass-git-helper, yamale removed (now in nixpkgs)
final: prev: {

  # cmdperf: command performance benchmarking (hyperfine-style). Not in
  # nixpkgs. Pure Go, upstream builds with CGO disabled; goreleaser's
  # default ldflags stamp main.version.
  cmdperf = prev.buildGoModule (finalAttrs: {
    pname = "cmdperf";
    version = "0.1.4";

    src = prev.fetchFromGitHub {
      owner = "miklosn";
      repo = "cmdperf";
      tag = "v${finalAttrs.version}";
      hash = "sha256-KNPf9LI1rUD6NY+gO1maTZwMPq/kCDl2tL2dMd5DOhc=";
    };

    vendorHash = "sha256-k0dvd34KiPNb/wViaaSUQy04LSIsxQHWNwLM5blfDMo=";

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
  gogcli = prev.gogcli.overrideAttrs (
    finalAttrs: _oldAttrs: {
      version = "0.31.1";
      src = prev.fetchFromGitHub {
        owner = "openclaw";
        repo = "gogcli";
        tag = "v${finalAttrs.version}";
        hash = "sha256-kTMxHPY3bv85X3H0TQGHLvL/nVVjh5fDF/S/z6Xd+bw=";
      };
      vendorHash = "sha256-fof2DVm6Cn1ZW7gKSYLHX6M6nPbtYBn6EKinptjhhrE=";
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
    version = "b5a7543b";
    rev = "b5a7543b4741d9b54dad49ecfca8908a4aedf124";
    sha256 = "sha256-SGHB8UTJ9cT/hZiv4V/rc3GwKlB6r9WCYsMXFA+Iw4c=";
    description = "A tool for fixing broken symlinks";
  };

  linkdups = prev.myLib.mkSimpleGitHubBinary {
    pname = "linkdups";
    version = "e1d5b82d";
    rev = "e1d5b82da048300a78f2fc7d62f200bbfc5d973b";
    sha256 = "sha256-N0MAdqn8yHrEvAbbtfHhToa9Kefs6LSwA/tVPUzWOSs=";
    description = "A tool for hard-linking duplicate files";
  };

  lipotell = prev.myLib.mkSimpleGitHubBinary {
    pname = "lipotell";
    version = "1502a475";
    rev = "1502a4753f42618efcf2d0d561c818af377b0d92";
    sha256 = "sha256-TnaiGFXRzc4hwSgKvmxHJcCQW6H9Qh7VWQL+RoFb024=";
    description = "A tool to find large files within a directory";
  };

  sift = prev.myLib.mkSimpleGitHubBinary {
    pname = "sift";
    version = "c823f340";
    rev = "c823f340be8818cc7aa970f9da4c81247f5b5535";
    sha256 = "1yadjgjcghi2fhyayl3ry67w3cz6f7w0ibni9dikdp3vnxp94y58";
    description = "A tool for sifting apart large patch files";
  };

  sshify = prev.myLib.mkSimpleGitHubBinary {
    pname = "sshify";
    version = "a6fb0d52";
    rev = "a6fb0d529ec01158dd031431099b0ba8c8d64eb6";
    sha256 = "sha256-wl2BZhVIpIFrcReQrMbkbxkrPA7vKKdkPfAYo5IlbIs=";
    description = "A tool for installing SSH authorized_key on remote servers";
  };

  # Track most-used directories based on frecency
  z =
    with prev;
    stdenv.mkDerivation rec {
      name = "z-${version}";
      version = "d37a763a";

      src = fetchFromGitHub {
        owner = "rupa";
        repo = "z";
        rev = "d37a763a6a30e1b32766fecc3b8ffd6127f8a0fd";
        sha256 = "10azqw3da1mamfxhx6r0x481gsnjjipcfv6q91vp2bhsi22l35hy";
        # date = 2023-12-09T17:41:33-05:00;
      };

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
