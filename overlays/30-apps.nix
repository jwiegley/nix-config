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
    meta = with stdenv.lib; {
      description = description;
      homepage = homepage;
      maintainers = with maintainers; [ jwiegley ];
      platforms = platforms.darwin;
    };
  };

Anki = self.installApplication rec {
  name = "Anki";
  version = "2.1.8";
  sourceRoot = "Anki.app";
  src = super.fetchurl {
    url = "https://apps.ankiweb.net/downloads/current/anki-${version}-mac.dmg";
    sha256 = "15fzbgbcl03pkkix0i9g5f1402gyc0rq06if80pvhi70vks7c27b";
    # date = 2019-01-23T15:42:49-0800;
  };
  description = "Anki is a program which makes remembering things easy";
  homepage = https://apps.ankiweb.net;
};

Dash = self.installApplication rec {
  name = "Dash";
  version = "4.6.2";
  sourceRoot = "Dash.app";
  src = super.fetchurl {
    url = https://kapeli.com/downloads/v4/Dash.zip;
    sha256 = "0l0ccxxl8zvpdyacj1rndlqmzhwm2zqjj5a8qvj4mjbjmiimlb40";
    # date = 2019-02-07T13:34:58-0800;
  };
 description = "Dash is an API Documentation Browser and Code Snippet Manager";
  homepage = https://kapeli.com/dash;
};

Docker = self.installApplication rec {
  name = "Docker";
  version = "2.0.0.2";
  sourceRoot = "Docker.app";
  src = super.fetchurl {
    url = https://download.docker.com/mac/stable/Docker.dmg;
    sha256 = "0km0q18hia8asj7rgg3fsck74fzd6xqbhv3qhfqphdwwvbc0fqx0";
    # date = 2019-01-23T08:50:30-0800;
  };
  description = ''
    Docker CE for Mac is an easy-to-install desktop app for building,
    debugging, and testing Dockerized apps on a Mac
  '';
  homepage = https://store.docker.com/editions/community/docker-ce-desktop-mac;
};

Firefox = self.installApplication rec {
  name = "Firefox";
  version = "65.0.1";
  sourceRoot = "Firefox.app";
  src = super.fetchurl {
    name = "Firefox-${version}.dmg";
    url = "https://download-installer.cdn.mozilla.net/pub/firefox/releases/${version}/mac/en-US/Firefox%20${version}.dmg";
    sha256 = "1qpsci58ckvfgwqdrdw3ybqi12mhnf90cgfyvyqqv5nmzbr5kgyb";
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
  major = "2.10";
  minor = "4";
  version = "${major}.${minor}";
  sourceRoot = "Gimp-${major}.app";
  src = super.fetchurl {
    url = "https://download.gimp.org/mirror/pub/gimp/v${major}/osx/gimp-${version}-x86_64.dmg";
    sha256 = "0sv9z5a5y54qvnf1a0wgr60bpwxn17gghd1djrlg2xplp443ddzp";
    # date = 2018-02-04T13:08:53-0800;
  };
  description = "GIMP is a cross-platform image editor";
  homepage = https://www.gimp.org;
};

HandBrake = self.installApplication rec {
  name = "HandBrake";
  version = "1.1.2";
  sourceRoot = "HandBrake.app";
  src = super.fetchurl {
    url = "https://download2.handbrake.fr/${version}/HandBrake-${version}.dmg";
    sha256 = "0s5k0rj8m53vyxn4gd68ca5bic9z311wr9wdrhalpn476r2fn7qq";
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
  version = "3.2.7";
  sourceRoot = "iTerm.app";
  src = super.fetchurl {
    url = "https://iterm2.com/downloads/stable/iTerm2-3_2_7.zip";
    sha256 = "1q9agvyl0zv8y6bbjnjyxll0fc23wnysjjn661xbi3rpp7sdswdc";
    # date = 2019-01-22T10:40:39-0800;
  };
  description = "iTerm2 is a replacement for Terminal and the successor to iTerm";
  homepage = https://www.iterm2.com;
};

KeyboardMaestro = self.installApplication rec {
  name = "KeyboardMaestro";
  appname = "Keyboard Maestro";
  version = "8.2.4";
  sourceRoot = "Keyboard Maestro.app";
  src = super.fetchurl {
    url = http://files.stairways.com/keyboardmaestro-824.zip;
    sha256 = "0wv3vbvrs9rc2ln0dg4830izx0gmsf4d73ni298wkd98fs7c4is5";
    # date = 2018-08-09T18:46:48-0400;
  };
  description = "Keyboard macro program for macOS";
  homepage = https://www.keyboardmaestro.com;
};

PathFinder = self.installApplication rec {
  name = "PathFinder";
  appname = "Path Finder";
  version = "7.6.2";
  sourceRoot = "Path Finder.app";
  src = super.fetchurl {
    url = "http://get.cocoatech.com/PF7.zip";
    sha256 = "0m1dz8i9af1lvcdj5fd8wc77qr18zx40pq9c27zss34yjr7r0mq7";
    # date = 2018-02-04T22:21:12-0800;
  };
  description = "File manager for macOS";
  homepage = https://cocoatech.com;
};

RipIt = self.installApplication rec {
  name = "RipIt";
  version = "1.6.9";
  sourceRoot = "RipIt.app";
  src = super.fetchurl {
    url = http://files.thelittleappfactory.com/ripit/RipIt.zip;
    sha256 = "1g6h59y83f9fflb5kbdq2d47jiljn4ki69vl9cxajayv2q04b8vn";
    # date = 2018-02-04T23:39:18-0800;
  };
  description = "The simple DVD ripper for Macs";
  homepage = http://thelittleappfactory.com/ripit;
};

Skim = self.installApplication rec {
  name = "Skim";
  version = "1.4.40";
  sourceRoot = "Skim.app";
  src = super.fetchurl {
    name = "Skim-${version}.dmg";
    url = "https://sourceforge.net/projects/skim-app/files/Skim/Skim-${version}/Skim-${version}.dmg/download";
    sha256 = "1mgawkw0pfhicg98s2ydj1dinl8232g9lkkncj961j8fdr95qwaz";
    # date = 2019-01-23T15:50:51-0800;
  };
  description = "Skim is a PDF reader and note-taker for OS X";
  homepage = https://skim-app.sourceforge.io;
};

Slate = self.installApplication rec {
  name = "Slate";
  version = "1.0.25";
  sourceRoot = "Slate.app";
  src = super.fetchurl {
    url = http://slate.ninjamonkeysoftware.com/Slate.dmg;
    sha256 = "0gr27s0a150sy2rf0vqw0mw32k21wh4v7b1n2ngzfr0wbdfkg3j2";
    # date = 2019-02-07T09:26:28-0800;
  };
  description = ''
    A window management application (replacement for Divvy/SizeUp/ShiftIt)
  '';
  homepage = https://github.com/jigish/slate;
};

Soulver = self.installApplication rec {
  name = "Soulver";
  version = "2.6.8";
  sourceRoot = "Soulver.app";
  src = super.fetchurl {
    name = "soulver-${version}.zip";
    url = "http://www.acqualia.com/files/download.php?product=soulver";
    sha256 = "0ymb608j69ihs4a35zz3d5jqyc446nkffc0gp17ik0w727w10q91";
    # date = 2018-08-19T15:54:54-0800;
  };
  description = ''
    Use Soulver to play around with numbers, do "back of the envelope" quick
    calculations, and solve day-to-day problems.
  '';
  homepage = http://www.acqualia.com/soulver;
};

SuspiciousPackage = self.installApplication rec {
  name = "SuspiciousPackage";
  appname = "Suspicious Package";
  version = "3.4";
  sourceRoot = "Suspicious Package.app";
  src = super.fetchurl {
    url = "http://www.mothersruin.com/software/downloads/SuspiciousPackage.dmg";
    sha256 = "0jq9x6rs3j6qvw4phar65law50r2vp58znc92xqwnz8fb463lrz4";
    # date = 2019-01-07T14:10:49-0800;
  };
  description = "An Application for Inspecting macOS Installer Packages";
  homepage = http://www.mothersruin.com/software/SuspiciousPackage;
};

Ukelele = self.installApplication rec {
  name = "Ukelele";
  version = "3.2.7";
  sourceRoot = "Ukelele.app";
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
  version = "1.20";
  sourceRoot = "UnicodeChecker ${version}/UnicodeChecker.app";
  src = super.fetchurl {
    url = http://earthlingsoft.net/UnicodeChecker/UnicodeChecker.zip;
    sha256 = "06v7qbb55zd2x9qmqr6ssnrsvsv97x9apq81vkbych4f5farwk2z";
    # date = 2018-08-21T12:44:03-0700;
  };
  description = "Explore and convert Unicode";
  homepage = http://earthlingsoft.net/UnicodeChecker;
};

VirtualII = self.installApplication rec {
  name = "VirtualII";
  appname = "Virtual ][";
  version = "9.0";
  sourceRoot = "Virtual ][.app";
  src = super.fetchurl {
    url = http://www.virtualii.com/VirtualII.dmg;
    sha256 = "0sqdjrcf7wk847p4pzaj5gh2wccgq5hfbi72xsdq5p53dn8696hl";
    # date = 2019-01-24T11:34:12-0800;
  };
  description = ''
    Virtual ][ lets you play the old Apple games, because it supports all
    graphics modes, lets you control the game paddles with a USB game pad or
    mouse and emulates the internal speaker. When you want to temporarily
    interrupt gameplay, Virtual ][ allows you to save the entire virtual
    machine, and continue later on from where you left off.

    But Virtual ][ also supports more "serious" software, because it emulates
    many peripheral devices: floppy disk, hard disk, mouse, serial port,
    matrix printer, even cassette tape! It also emulates the Z80A processor,
    allowing you to run the CP/M operating system.
  '';
  homepage = http://www.virtualii.com;
};

Zekr = self.installApplication rec {
  name = "Zekr";
  version = "1.1.0";
  sourceRoot = "Zekr.app";
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
  version = "5.0.55";
  sourceRoot = "Zotero.app";
  src = super.fetchurl {
    name = "zotero-${version}.dmg";
    url = "https://www.zotero.org/download/client/dl?channel=release&platform=mac&version=${version}";
    sha256 = "1i42i5fcgv7d7g8dns0m557fvgbpcs6bvsiqq2fs7cacdxhl92ci";
  };
  description = ''
    Zotero is a free, easy-to-use tool to help you collect, organize, cite,
    and share your research sources
  '';
  homepage = https://www.zotero.org;
};

}
