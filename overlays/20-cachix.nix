self: super: {

cachix =
  let src = super.fetchFromGitHub {
        owner = "cachix";
        repo = "cachix";
        rev = "5523187c07dc7ae8ca0be5c6105dc86584cb87de";
        sha256 = "022igls08khlf7zw80qx4lpljz4d3slzwnkz942p1ls7ba3yb7jl";
        # date = 2019-11-13T17:32:53+01:00;
      };
      cachix = import src {};
  in
  cachix.cachix;

}
