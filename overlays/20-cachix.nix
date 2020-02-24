self: super: {

cachix =
  let src = super.fetchFromGitHub {
        owner = "cachix";
        repo = "cachix";
        rev = "4a4d5da86f1f8f066664669f8b982102f96118ec";
        sha256 = "12223icr9jal1nkmdqxpfnp8dx39y72dddq3l5aps64jpassvdvg";
        # date = 2020-02-19T07:54:14+01:00;
      };
      cachix = import src {};
  in
  cachix.cachix;

}
