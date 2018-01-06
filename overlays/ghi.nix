self: super: {

ghi = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "ghi";
  version = "1.2.0";
  sha256 = "05cirb2ndhh0i8laqrfwijprqy63gmxmd8agqkayvqpjs26gdbwi";
  buildInputs = [bundler];
};

}
