self: super: {

lorri =
  let src = super.fetchFromGitHub {
    owner  = "target";
    repo   = "lorri";
    rev    = "e943fa403234f1a5e403b6fdc112e79abc1e29ba";
    sha256 = "1ar7clza117qdzldld9qzg4q0wr3g20zxrnd1s51cg6gxwlpg7fa";
    # date = 2019-03-29T16:34:35+01:00;
  }; in
  import src { inherit src; pkgs = self; };

}
