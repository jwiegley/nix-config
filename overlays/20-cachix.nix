self: super: {

cachix =
  let src = super.fetchFromGitHub {
        owner = "cachix";
        repo = "cachix";
        rev = "cfc71ecd1322b922db9d60c49ac18f62555af06e";
        sha256 = "0jdmi80l632s1cf6pikp3a7yj3lxba2zpc6mnn6icgkl49bv37h4";
        # date = 2020-01-10T17:15:41+01:00;
      };
      cachix = import src {};
  in
  cachix.cachix;

}
