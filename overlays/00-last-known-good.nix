self: super:

let
  nixpkgs = { rev, sha256 }:
    import (super.fetchFromGitHub {
      owner  = "NixOS";
      repo   = "nixpkgs";
      inherit rev sha256;
    }) { config.allowUnfree = true; };

  known-good-20181208_134904 = nixpkgs {
    rev    = "61c3169a0e17d789c566d5b241bfe309ce4a6275";
    sha256 = "0qbycg7wkb71v20rchlkafrjfpbk2fnlvvbh3ai9pyfisci5wxvq";
  };

  known-good-20190131_115636 = nixpkgs {
    rev    = "120eab94e0981758a1c928ff81229cd802053158";
    sha256 = "0qk6k8gxx5xlkyg05dljywj5wx5fvrc3dzp4v2h6ab83b7zwg813";
  };

  known-good-20190211_193052 = nixpkgs {
    rev    = "1a88aa9e0cdcbc12acc5cbdc379c0804d208e913";
    sha256 = "076zlppa0insiv9wklk4h45m7frq1vfs43vsa11l8bm5i5qxzk6r";
  };

in
{
  inherit (known-good-20181208_134904) zbar xquartz;

  inherit (known-good-20190211_193052) xapian;

  gitAndTools = super.gitAndTools // {
    inherit (known-good-20190131_115636.gitAndTools) git-annex;
  };

  haskell = super.haskell // {
    compiler = super.haskell.compiler // {
      inherit (known-good-20190131_115636.haskell.compiler) ghc844 ghc822;
    };
  };
}
