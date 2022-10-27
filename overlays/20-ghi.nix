self: super: {

pygments.rb = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "pygments.rb";
  version = "2.3.0";
  source.sha256 = "sha256-TEHIuu4QaA2Aiy/amyNv5rJ5nNTOXBXim5Ns9L+X9RA=";
  buildInputs = [ bundler ];
};

multi_json = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "multi_json";
  version = "1.15.0";
  source.sha256 = "sha256-H9BBOLbkqQAX6NG4BMA5AxOZhm/z+6u3girqNnx4YV0=";
  buildInputs = [ bundler ];
};

ghi = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "ghi";
  version = "1.2.1";
  src = fetchFromGitHub {
    owner = "drazisil";
    repo = "ghi";
    rev = "886479e122f1175f8587c1eb86d19e1aa571c76e";
    sha256 = "1s0bwk2rcb6rbck0xgbsyi7m6cw8qbjigclrcd79pmv3zczpq2n2";
    # date = "2022-03-20T20:37:28-04:00";
  };
  buildInputs = [ bundler self.pygments.rb self.multi_json ];
};

}
