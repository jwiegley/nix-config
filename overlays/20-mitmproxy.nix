self: super: {

mitmproxy = with self.python3Packages; buildPythonPackage rec {
  pname = "mitmproxy";
  version = "3.0.4";

  src = super.fetchFromGitHub {
    owner  = pname;
    repo   = pname;
    rev    = "v${version}";
    sha256 = "10l761ds46r1p2kjxlgby9vdxbjjlgq72s6adjypghi41s3qf034";
  };

  postPatch = ''
    # remove dependency constraints
    sed 's/>=\([0-9]\.\?\)\+\( \?, \?<\([0-9]\.\?\)\+\)\?//' -i setup.py
  '';

  checkPhase = ''
    export HOME=$(mktemp -d)
    export LC_CTYPE=en_US.UTF-8
    # test_echo resolves hostnames
    pytest -k 'not test_echo and not test_find_unclaimed_URLs '
  '';

  propagatedBuildInputs = [
    blinker click certifi cryptography
    h2 hyperframe kaitaistruct passlib
    pyasn1 pyopenssl pyparsing pyperclip
    ruamel_yaml tornado urwid brotlipy
    sortedcontainers ldap3 wsproto
  ];

  checkInputs = with self; [
    beautifulsoup4 flask pytest
    requests glibcLocales
  ];

  meta = with stdenv.lib; {
    description = "Man-in-the-middle proxy";
    homepage    = https://mitmproxy.org/;
    license     = licenses.mit;
    maintainers = with maintainers; [ fpletz kamilchm ];
  };
};

}
