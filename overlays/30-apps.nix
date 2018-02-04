self: super: {

installApplication = 
  { name, appname ? name, version, src, description, homepage, 
    postInstall ? "", ... }:
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
      if [[ $(find . -maxdepth 1 -name '*.app' -type d | wc -l) == 0 ]]; then
        mkdir -p "$out/Applications/${appname}.app"
        cp -pR * "$out/Applications/${appname}.app"
      else
        mkdir -p $out/Applications
        cp -pR *.app $out/Applications
      fi
    '' + postInstall;
    # postInstall = postInstall;
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

Firefox = self.installApplication rec {
  name = "Firefox";
  version = "58.0.1";
  src = super.fetchurl {
    name = "Firefox-${version}.dmg";
    url = "https://download-installer.cdn.mozilla.net/pub/firefox/releases/${version}/mac/en-US/Firefox%20${version}.dmg";
    sha256 = "1ddjrfvka4gc20s5n66z4r4wxmcrwdw4ckfkjx5j7kwsjw2gfld7";
    # date = 2018-02-02T15:42:49-0800;
  };
  postInstall = ''
    for file in  \
        $out/Applications/Firefox.app/Contents/MacOS/firefox \
        $out/Applications/Firefox.app/Contents/MacOS/firefox-bin
    do
        dir=$(dirname "$file")
        base=$(basename "$file")
        mv $file $dir/.$base

        cat > $file <<'EOF'
#!/bin/bash
export PATH=${super.gnupg}/bin:${super.pass}/bin:$PATH
export PASSWORD_STORE_ENABLE_EXTENSIONS="true"
export PASSWORD_STORE_EXTENSIONS_DIR="/run/current-system/sw/lib/password-store/extensions";
export PASSWORD_STORE_DIR="$HOME/Documents/.passwords";
export GNUPGHOME="$HOME/.config/gnupg"
export GPG_TTY=$(tty)
if ! pgrep -x "gpg-agent" > /dev/null; then
${super.gnupg}/gpgconf --launch gpg-agent
fi
dir=$(dirname "$0")
name=$(basename "$0")
exec "$dir"/."$name" "$@"
EOF
        chmod +x $file
    done
  '';
  description = "Anki is a program which makes remembering things easy";
  homepage = https://apps.ankiweb.net/;
};

GIMP = self.installApplication rec {
  name = "GIMP";
  major = "2.8";
  minor = "22";
  version = "${major}.${minor}";
  src = super.fetchurl {
    url = "https://download.gimp.org/mirror/pub/gimp/v${major}/osx/gimp-${version}-x86_64.dmg";
    sha256 = "05mxwimvym4afpzj32lp0yjlac5m39nmmxa775wvaqmjah69c51l";
    # date = 2018-02-04T13:08:53-0800;
  };
  description = "GIMP is a cross-platform image editor";
  homepage = https://www.gimp.org/;
};

# SageMath = self.installApplication rec {
#   name = "SageMath";
#   version = "8.1";
#   src = super.fetchurl {
#     url = "http://mirrors.xmission.com/sage/osx/intel/sage-${version}-OSX_10.12.6-x86_64.dmg";
#     sha256 = "163gdv3iylf5l7vl5zd1a80az8pnlbilqcmhwgjqjf44rr5krk0k";
#     # date = 2018-02-04T13:08:53-0800;
#   };
#   description = "GIMP is a cross-platform image editor";
#   homepage = https://www.gimp.org/;
# };

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
