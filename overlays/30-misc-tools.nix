# overlays/30-misc-tools.nix
# Purpose: Miscellaneous utility tools (file management, shell, security)
# Dependencies: None (uses only prev)
# Packages: hammer, linkdups, lipotell, sift, sshify, z, pass-git-helper, yamale
final: prev: {

  # Fix broken symlinks
  hammer =
    with prev;
    stdenv.mkDerivation rec {
      name = "hammer-${version}";
      version = "b5a7543b";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "hammer";
        rev = "b5a7543b4741d9b54dad49ecfca8908a4aedf124";
        sha256 = "sha256-SGHB8UTJ9cT/hZiv4V/rc3GwKlB6r9WCYsMXFA+Iw4c=";
        # date = 2011-09-10T19:08:08-05:00;
      };

      phases = [
        "unpackPhase"
        "installPhase"
      ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p hammer $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/hammer";
        description = "A tool for fixing broken symlinks";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # Hard-link duplicate files to save space
  linkdups =
    with prev;
    stdenv.mkDerivation rec {
      name = "linkdups-${version}";
      version = "e1d5b82d";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "linkdups";
        rev = "e1d5b82da048300a78f2fc7d62f200bbfc5d973b";
        sha256 = "sha256-N0MAdqn8yHrEvAbbtfHhToa9Kefs6LSwA/tVPUzWOSs=";
        # date = 2025-05-13T11:29:24-07:00;
      };

      phases = [
        "unpackPhase"
        "installPhase"
      ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p linkdups $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/linkdups";
        description = "A tool for hard-linking duplicate files";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # Find large files within a directory
  lipotell =
    with prev;
    stdenv.mkDerivation rec {
      name = "lipotell-${version}";
      version = "1502a475";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "lipotell";
        rev = "1502a4753f42618efcf2d0d561c818af377b0d92";
        sha256 = "sha256-TnaiGFXRzc4hwSgKvmxHJcCQW6H9Qh7VWQL+RoFb024=";
        # date = 2011-09-10T18:57:01-05:00;
      };

      phases = [
        "unpackPhase"
        "installPhase"
      ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p lipotell $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/lipotell";
        description = "A tool to find large files within a directory";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # Sift apart large patch files
  sift =
    with prev;
    stdenv.mkDerivation rec {
      name = "sift-${version}";
      version = "c823f340";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "sift";
        rev = "c823f340be8818cc7aa970f9da4c81247f5b5535";
        sha256 = "1yadjgjcghi2fhyayl3ry67w3cz6f7w0ibni9dikdp3vnxp94y58";
        # date = 2011-09-10T19:05:37-05:00;
      };

      phases = [
        "unpackPhase"
        "installPhase"
      ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p sift $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/sift";
        description = "A tool for sifting apart large patch files";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # Install SSH authorized_keys on remote servers
  sshify =
    with prev;
    stdenv.mkDerivation rec {
      name = "sshify-${version}";
      version = "a6fb0d52";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "sshify";
        rev = "a6fb0d529ec01158dd031431099b0ba8c8d64eb6";
        sha256 = "sha256-wl2BZhVIpIFrcReQrMbkbxkrPA7vKKdkPfAYo5IlbIs=";
        # date = 2018-01-27T17:11:59-08:00;
      };

      phases = [
        "unpackPhase"
        "installPhase"
      ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p sshify $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/sshify";
        description = "A tool for installing SSH authorized_key on remote servers";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
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

  # Git credential helper using pass password manager
  pass-git-helper =
    with prev;
    with python3Packages;
    buildPythonPackage rec {
      pname = "pass-git-helper";
      version = "ccb30de0";

      src = fetchFromGitHub {
        owner = "languitar";
        repo = "pass-git-helper";
        rev = "ccb30de0606107579badf38081810a033a7ca288";
        sha256 = "sha256-/Brx86YRmSkSr00xj5B5J/bNBqknoXRwX9B6595dEwU=";
        # date = 2025-10-02T16:40:46+02:00;
      };

      dependencies = [
        pyxdg
      ];
      doCheck = false;

      pyproject = true;
      build-system = [ setuptools ];

      meta = {
        homepage = "https://github.com/languitar/pass-git-helper";
        description = "A git credential helper interfacing with pass, the standard unix password manager";
        license = lib.licenses.lgpl3;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # YAML schema validator
  yamale =
    with prev;
    with python3Packages;
    buildPythonPackage rec {
      pname = "yamale";
      version = "c203d14b";

      src = fetchFromGitHub {
        owner = "23andMe";
        repo = "Yamale";
        rev = "c203d14bface6f35693874a8e4ee39079bcb9094";
        sha256 = "sha256-/Ax6EYZH8SEWJ2RIGOW7cotuALDaG/w/4twsXG+VSTw=";
        # date = 2025-10-27T13:56:16-04:00;
      };

      dependencies = [ pyyaml ];

      pyproject = true;
      build-system = [ setuptools ];

      meta = {
        homepage = "https://github.com/23andMe/Yamale";
        description = "A schema and validator for YAML";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # Google Suite CLI: Gmail, GCal, GDrive, GContacts
  gogcli =
    with prev;
    (buildGoModule.override { go = go_1_26; }) rec {
      pname = "gogcli";
      version = "0.12.0";

      src = fetchFromGitHub {
        owner = "steipete";
        repo = "gogcli";
        rev = "v${version}";
        hash = "sha256-KtjqZLR4Uf77865IGHFmcjwpV8GWkiaV7fBeTrsx93E=";
      };

      vendorHash = "sha256-8RKzJq4nlg7ljPw+9mtiv0is6MeVtkMEiM2UUdKPP3U=";

      doCheck = false;

      meta = {
        homepage = "https://github.com/steipete/gogcli";
        description = "Google Suite CLI: Gmail, GCal, GDrive, GContacts";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
