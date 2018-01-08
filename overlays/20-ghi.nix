self: super: rec {

pygments.rb = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "pygments.rb";
  version = "1.2.1";
  sha256 = "0lbvnwvz770ambm4d6lxgc2097rydn5rcc5d6986bnkzyxfqqjnv";
  buildInputs = [ bundler ];
};

multi_json = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "multi_json";
  version = "1.12.2";
  sha256 = "1raim9ddjh672m32psaa9niw67ywzjbxbdb8iijx3wv9k5b0pk2x";
  buildInputs = [ bundler ];
};

ghi = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "ghi";
  version = "1.2.0";
  sha256 = "05cirb2ndhh0i8laqrfwijprqy63gmxmd8agqkayvqpjs26gdbwi";
  buildInputs = [ bundler pygments.rb multi_json ];
};

}
