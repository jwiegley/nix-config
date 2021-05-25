{ foo    ? null
, rev    ? "970b2b853d41ec80a3c2aba3e585f52818fbbfa3"
, sha256 ? "0cwm2gvnb7dfw9pjrwzlxb2klix58chc36nnymahjqaa1qmnpbpq"
, pkgs   ? import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz";
    inherit sha256; }) {
    config.allowUnfree = true;
    config.allowBroken = false;
  }
}:
{ inherit (pkgs) coreutils; }
