self: super: {

pycoingecko = with super; with python3Packages; buildPythonPackage rec {
  pname = "coingecko";
  version = "618289c0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "man-c";
    repo = "pycoingecko";
    rev = "6f6d0ba959a2b884dcc3575700001ad01fe8fa25";
    sha256 = "1nacmlc0c68s54qzr4fm77rwbr6m1rj8nzrycxgggk5mrs9gs5dp";
    # date = 2021-06-17T11:45:02+03:00;
  };

  propagatedBuildInputs = [ requests ];
  buildInputs = [ pytest ];

  meta = {
    homepage = https://github.com/man-c/pycoingecko;
    description = "Python3 wrapper around the CoinGecko API (V3)";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
