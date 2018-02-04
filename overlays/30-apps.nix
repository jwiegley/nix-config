self: super: {

installApplication = 
  { name, appname ? name, version, src, description, homepage }:
  with super; stdenv.mkDerivation {
    name = "${name}-${version}";
    version = "${version}";
    src = src;
    buildInputs = [ undmg ];
    phases = [ "unpackPhase" "installPhase" ];
    unpackPhase = ''
      undmg < "${src}"
    '';
    installPhase = ''
      if [[ $(find . -maxdepth 1 -name '*xapp' -type d | wc -l) == 0 ]]; then
        mkdir -p "$out/Applications/${appname}.app"
        cp -pR * "$out/Applications/${appname}.app"
      else
        mkdir -p $out/Applications
        cp -pR *.app $out/Applications
      fi
    '';
    meta = with stdenv.lib; {
      description = description;
      homepage = homepage;
      maintainers = with maintainers; [ jwiegley ];
      platforms = platforms.darwin;
    };
  };

Anki = self.installApplication rec {
  name = "Anki";
  version = "2.1.0beta35";
  src = super.fetchurl {
    url = "https://apps.ankiweb.net/downloads/beta/anki-${version}.dmg";
    sha256 = "04q9pv182ajvgj79ffad8618wf75lpx4xq7sn5chb4sws66r5yky";
    # date = 2018-02-02T15:42:49-0800;
  };
  description = "Anki is a program which makes remembering things easy";
  homepage = https://apps.ankiweb.net/;
};

VLC = self.installApplication rec {
  name = "VLC";
  version = "2.2.8";
  src = super.fetchurl {
    url = "https://get.videolan.org/vlc/${version}/macosx/vlc-${version}.dmg";
    sha256 = "09x0sbzrs1sknw6bd549zgfq15ir7q6hflqyn4x71ib6qljy01j4";
    # date = 2018-02-04T13:08:53-0800;
  };
  description = "VLC is a free and open source cross-platform multimedia player";
  homepage = https://www.videolan.org/vlc;
};

}
