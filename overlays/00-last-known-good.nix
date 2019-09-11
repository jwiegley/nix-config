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

  known-good-20190305_133437 = nixpkgs {
    rev    = "b36dc66bfea6b0a733cf13bed85d80462d39c736";
    sha256 = "1f7vmhdipf0zz19lwx3ni0lmilhnild7r387a04ng92hnc27nnsv";
  };

  known-good-20190823_110501 = nixpkgs {
    rev    = "9103b70a933cc1f741ab078ddc0d73000e4ff794";
    sha256 = "1zb0ki280frcn64rkh0gs2g0iqgk0p1brkah2iql8nfd08msmxzj";
  };

  known-good-20190831_155518 = nixpkgs {
    rev    = "c4adeddb5f8e945517068968d06ea838b7c24bd3";
    sha256 = "1vpm73y7d0j2cviq0cgjwdj64h2v0c349capiyqf5f6071anx7d7";
  };

in
{
  inherit (known-good-20190305_133437) recoll socat2pre;
  inherit (known-good-20190831_155518) mitmproxy;

  gitAndTools = super.gitAndTools // {
    inherit (known-good-20190131_115636.gitAndTools) git-annex;
  };
}
