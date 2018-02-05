self: super: {

installApplication = 
  { name, appname ? name, version, src, description, homepage, 
    postInstall ? "", sourceRoot ? ".", ... }:
  with super; stdenv.mkDerivation {
    name = "${name}-${version}";
    version = "${version}";
    src = src;
    buildInputs = [ undmg unzip ];
    sourceRoot = sourceRoot;
    phases = [ "unpackPhase" "installPhase" ];
    installPhase = ''
      mkdir -p "$out/Applications/${appname}.app"
      cp -pR * "$out/Applications/${appname}.app"
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
  homepage = https://apps.ankiweb.net;
};

Firefox = self.installApplication rec {
  name = "Firefox";
  version = "58.0.1";
  sourceRoot = "Firefox.app";
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
  homepage = https://apps.ankiweb.net;
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
  homepage = https://www.gimp.org;
};

HandBrake = self.installApplication rec {
  name = "HandBrake";
  version = "1.0.7";
  sourceRoot = "HandBrake.app";
  src = super.fetchurl {
    url = "https://download2.handbrake.fr/${version}/HandBrake-${version}.dmg";
    sha256 = "1ql9xx9bh88c0xhsva2bsmdnxix3cw7lmm6wfjak84d2ilifdliw";
    # date = 2018-02-04T15:50:05-0800;
  };
  description = ''
    HandBrake is a tool for converting video from nearly any format to a
    selection of modern, widely supported codecs
  '';
  homepage = https://handbrake.fr;
};

iTerm2 = self.installApplication rec {
  name = "iTerm2";
  appname = "iTerm";
  version = "3.1.6beta1";
  src = super.fetchurl {
    url = "https://iterm2.com/downloads/beta/iTerm2-3_1_6beta1.zip";
    sha256 = "1hsgib46f098s10gg2s2810vpyj9c89qs0aivhrpgvp2vm84jhas";
    # date = 2018-02-04T15:47:24-0800;
  };
  description = "iTerm2 is a replacement for Terminal and the successor to iTerm";
  homepage = https://www.iterm2.com;
};

# LaTeXiT = self.installApplication rec {
#   name = "LaTeXiT";
#   version = "2.8.1";
#   src = super.fetchurl {
#     url = "https://www.chachatelier.fr/latexit/downloads/LaTeXiT-2_8_1.dmg";
#     sha256 = "error: unable to download 'https://www.chachatelier.fr/latexit/downloads/LaTeXiT-2_8_1.dmg': HTTP error 403 (curl error: No error)";
#     # date = 2018-02-04T14:46:50-0800;
#   };
#   description = "LaTeXiT is a graphical interface above a LaTeX engine";
#   homepage = https://www.chachatelier.fr/latexit;
# };

# SageMath = self.installApplication rec {
#   name = "SageMath";
#   version = "8.1";
#   src = super.fetchurl {
#     url = "http://mirrors.xmission.com/sage/osx/intel/sage-${version}-OSX_10.12.6-x86_64.dmg";
#     sha256 = "163gdv3iylf5l7vl5zd1a80az8pnlbilqcmhwgjqjf44rr5krk0k";
#     # date = 2018-02-04T13:08:53-0800;
#   };
#   description = "GIMP is a cross-platform image editor";
#   homepage = https://www.gimp.org;
# };

Slate = self.installApplication rec {
  name = "Slate";
  version = "1.0.25";
  src = super.fetchurl {
    url = "http://slate.ninjamonkeysoftware.com/Slate.dmg";
    sha256 = "0gr27s0a150sy2rf0vqw0mw32k21wh4v7b1n2ngzfr0wbdfkg3j2";
    # date = 2018-02-04T15:50:51-0800;
  };
  description = ''
    A window management application (replacement for Divvy/SizeUp/ShiftIt)
  '';
  homepage = https://github.com/jigish/slate;
};

SuspiciousPackage = self.installApplication rec {
  name = "SuspiciousPackage";
  appname = "Suspicious Package";
  version = "3.3.1";
  src = super.fetchurl {
    url = "http://www.mothersruin.com/software/downloads/SuspiciousPackage.dmg";
    sha256 = "0133l1v1x3pv9bhjpf7nqh8gsiyz1j1abgil6p8bcx05jgffdvj9";
    # date = 2018-02-04T16:23:11-0800;
  };
  description = "An Application for Inspecting macOS Installer Packages";
  homepage = http://www.mothersruin.com/software/SuspiciousPackage;
};

Transmission = self.installApplication rec {
  name = "Transmission";
  version = "896de2b593";
  sourceRoot = "Transmission.app";
  src = super.fetchurl {
    url = "https://build.transmissionbt.com/job/trunk-mac/lastSuccessfulBuild/artifact/release/Transmission-${version}.dmg";
    sha256 = "0c8yx461kbgwqzz3b97n2i9hk19sk6m9rh5r7r87a7dwwnmrcj32";
    # date = 2018-02-04T14:23:15-0800;
  };
  description = "Cross-platform BitTorrent client";
  homepage = https://transmissionbt.com;
};

Ukelele = self.installApplication rec {
  name = "Ukelele";
  version = "3.2.7";
  src = super.fetchurl {
    name = "Ukelele-${version}.dmg";
    url = "http://scripts.sil.org/cms/scripts/render_download.php?format=file&media_id=Ukelele_${version}&filename=Ukelele_${version}.dmg";
    sha256 = "0ga4sy6z52fqgdvckpsbvz1xnd6gpsk1d8pziw4nf68y7q9a7mjz";
    # date = 2018-02-04T16:15:00-0800;
  };
  description = "Ukelele is a Unicode Keyboard Layout Editor for Mac OS X";
  homepage = http://scripts.sil.org/ukelele;
};

UnicodeChecker = self.installApplication rec {
  name = "UnicodeChecker";
  version = "1.19";
  sourceRoot = "UnicodeChecker ${version}/UnicodeChecker.app";
  src = super.fetchurl {
    url = http://earthlingsoft.net/UnicodeChecker/UnicodeChecker.zip;
    sha256 = "12rf6l62bxszxs8cq4259bi3n0iwmmg6rxqmff52i55qnbiqjb87";
    # date = 2018-02-04T16:15:00-0800;
  };
  description = "Explore and convert Unicode";
  homepage = http://earthlingsoft.net/UnicodeChecker;
};

VLC = self.installApplication rec {
  name = "VLC";
  version = "2.2.8";
  sourceRoot = "VLC.app";
  src = super.fetchurl {
    url = "https://get.videolan.org/vlc/${version}/macosx/vlc-${version}.dmg";
    sha256 = "09x0sbzrs1sknw6bd549zgfq15ir7q6hflqyn4x71ib6qljy01j4";
    # date = 2018-02-04T13:08:53-0800;
  };
  description = "VLC is a free and open source cross-platform multimedia player";
  homepage = https://www.videolan.org/vlc;
};

Zekr = self.installApplication rec {
  name = "Zekr";
  version = "1.1.0";
  src = super.fetchurl {
    name = "zekr-${version}-mac_64.tgz";
    url = "http://sourceforge.net/projects/zekr/files/Zekr/zekr-${version}/zekr-${version}-mac_64.tgz/download";
    sha256 = "0615cw21da3bxwyws718y889h9hdcy50s5r7famjj3i51w1zrhcm";
    # date = 2018-02-04T15:38:19-0800;
  };
  description = "Open-source Holy Qur'an browser for the Mac";
  homepage = http://zekr.org/quran/en/quran-for-mac;
};

Zotero = self.installApplication rec {
  name = "Zotero";
  version = "5.0.34.6";
  src = super.fetchurl {
    name = "zotero-${version}.dmg";
    url = "https://www.zotero.org/download/client/dl?channel=release&platform=mac&version=5.0.34.6";
    sha256 = "0dcphxhi2f566cqn5avihwp63kijs2wj49zccafcl8gllw861y4p";
    # date = 2018-02-04T15:54:54-0800;
  };
  description = ''
    Zotero is a free, easy-to-use tool to help you collect, organize, cite,
    and share your research sources
  '';
  homepage = https://www.zotero.org;
};

# Dash
# Deskzilla Lite

}
