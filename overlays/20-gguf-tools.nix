self: super: {

gguf-tools = with super; stdenv.mkDerivation rec {
  name = "gguf-tools-${version}";
  version = "8fa6eb65";

  src = fetchFromGitHub {
    owner = "antirez";
    repo = "gguf-tools";
    rev = "8fa6eb65236618e28fd7710a0fba565f7faa1848";
    sha256 = "084xwlqa6qq8ns2fzxvmgxhacgv7wy1l4mppwsmk7ac5yg46z4fp";
    # date = 2025-01-09T16:46:11+01:00;
  };

  installPhase = ''
    mkdir -p $out/bin
    cp -p gguf-tools $out/bin
  '';

  meta = {
    homepage = https://github.com/antirez/gguf-tools;
    description = "This is a work in progress library to manipulate GGUF files";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
