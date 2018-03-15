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
  version = "2.1.0beta35";
  sourceRoot = "Anki.app";
  src = super.fetchurl {
    url = "https://apps.ankiweb.net/downloads/beta/anki-${version}.dmg";
    sha256 = "04q9pv182ajvgj79ffad8618wf75lpx4xq7sn5chb4sws66r5yky";
    # date = 2018-02-02T15:42:49-0800;
  };
  description = "Anki is a program which makes remembering things easy";
  homepage = https://apps.ankiweb.net;
};

Dash = self.installApplication rec {
  name = "Dash";
  version = "4.1.4";
  sourceRoot = "Dash.app";
  src = super.fetchurl {
    url = https://kapeli.com/downloads/v4/Dash.zip;
    sha256 = "05m0h7zkwb7biy324hsg89vls8l81axqy6hn8hhvm1hlnwc4v23h";
    # date = 2018-02-19T10:51:10-0800;
  };
 description = "Dash is an API Documentation Browser and Code Snippet Manager";
  homepage = https://kapeli.com/dash;
};

DeskzillaLite = self.installApplication rec {
  name = "DeskzillaLite";
  appname = "Deskzilla Lite";
  version = "3.2.1";
  sourceRoot = "Deskzilla Lite.app";
  src = super.fetchurl {
    url = https://d1.almworks.com/.files/deskzilla-lite-3_2_1.dmg;
    sha256 = "0w2hqmznsk3qic2c6f3cycvmjpgvscckd9b0ljqfcrhkla4bv505";
    # date = 2018-02-04T16:36:09-0800;
  };
  description = ''
    Deskzilla is a desktop client for Mozilla's Bugzilla bug tracking system
  '';
  homepage = http://almworks.com/deskzilla;
};

DEVONagentPro = super.stdenv.lib.overrideDerivation (self.installApplication rec {
  name = "DEVONagentPro";
  appname = "DEVONagent";
  version = "3.9.8";
  sourceRoot = "DEVONagent.app";
  src = super.fetchurl {
    url = "https://s3.amazonaws.com/DTWebsiteSupport/download/devonagent/${version}/DEVONagent_Pro.dmg.zip";
    sha256 = "0wr7is69q9vn6kzg624kx1zs7jp2rx3f85xfzhqhg8pzlhrdv4cr";
    # date = 2018-02-05T00:00:54-0800;
  };
  description = ''
    DEVONagent Pro helps you search more efficiently on the web. It searches
    multiple sources, frees you from hunting for the really relevant results,
    and gives you power tools for your research.
  '';
  homepage = http://www.devontechnologies.com/products/devonagent/devonagent-pro.html;
}) (attrs: {
  unpackPhase = ''
    unzip -q ${attrs.src}
    undmg < DEVONagent_Pro.dmg
  '';
});

DEVONthinkPro = super.stdenv.lib.overrideDerivation (self.installApplication rec {
  name = "DEVONthinkPro";
  appname = "DEVONthink Pro";
  version = "2.9.17";
  sourceRoot = "DEVONthink Pro.app";
  src = super.fetchurl {
    url = "https://s3.amazonaws.com/DTWebsiteSupport/download/devonthink/${version}/DEVONthink_Pro.dmg.zip";
    sha256 = "04iz6z65czir80nc22b47qdqk2132cjbmi6sq2njkjb407wmyq0d";
    # date = 2018-02-04T23:54:35-0800;
  };
  description = ''
    DEVONthink Pro Office is your Mac paperless office. It stores all your
    documents, helps you keep them organized, and presents you with what you
    need to get the job done.
  '';
  homepage = http://www.devontechnologies.com/products/devonthink/devonthink-pro-office.html;
}) (attrs: {
  unpackPhase = ''
    unzip -q ${attrs.src}
    undmg < DEVONthink_Pro.dmg
  '';
});

Docker = self.installApplication rec {
  name = "Docker";
  version = "17.12.0-ce-mac49";
  sourceRoot = "Docker.app";
  src = super.fetchurl {
    url = https://download.docker.com/mac/stable/Docker.dmg;
    sha256 = "0dvr3mlvrwfc9ab6dyx351vraqx01lzxgz8vrczs0vhm2rpv3kdy";
    # date = 2018-02-04T16:36:09-0800;
  };
  description = ''
    Docker CE for Mac is an easy-to-install desktop app for building,
    debugging, and testing Dockerized apps on a Mac
  '';
  homepage = https://store.docker.com/editions/community/docker-ce-desktop-mac;
};

Firefox = self.installApplication rec {
  name = "Firefox";
  version = "59.0";
  sourceRoot = "Firefox.app";
  src = super.fetchurl {
    name = "Firefox-${version}.dmg";
    url = "https://download-installer.cdn.mozilla.net/pub/firefox/releases/${version}/mac/en-US/Firefox%20${version}.dmg";
    sha256 = "1jj0dwb93b8ajqv3igxv3x3w3cqp5d7xanr7wy9k0bqa0gr4414j";
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
  sourceRoot = "GIMP.app";
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
  sourceRoot = "iTerm.app";
  src = super.fetchurl {
    url = "https://iterm2.com/downloads/beta/iTerm2-3_1_6beta1.zip";
    sha256 = "1hsgib46f098s10gg2s2810vpyj9c89qs0aivhrpgvp2vm84jhas";
    # date = 2018-02-04T15:47:24-0800;
  };
  description = "iTerm2 is a replacement for Terminal and the successor to iTerm";
  homepage = https://www.iterm2.com;
};

KeyboardMaestro = self.installApplication rec {
  name = "KeyboardMaestro";
  appname = "Keyboard Maestro";
  version = "8.1.1";
  sourceRoot = "Keyboard Maestro.app";
  src = super.fetchurl {
    url = http://files.stairways.com/keyboardmaestro-811.zip;
    sha256 = "1mcwcqsi7nnk4vdvy611j167j7qxjmzal2nr83h66fplln7bqwjn";
    # date = 2018-02-20T11:06:21-0800;
  };
  description = "Keyboard macro program for macOS";
  homepage = https://www.keyboardmaestro.com;
};

LaTeXiT = self.installApplication rec {
  name = "LaTeXiT";
  version = "2.8.1";
  sourceRoot = "LaTeXiT.app";
  src = super.fetchurl {
    url = https://www.chachatelier.fr/latexit/downloads/LaTeXiT-2_8_1.dmg;
    sha256 = "1jpgz61w8p2kz7gvlxjnh0f91nwl2ap826kfgw5zdd2pznnwnb5b";
    # date = 2018-02-04T14:46:50-0800;
  };
  description = "LaTeXiT is a graphical interface above a LaTeX engine";
  homepage = https://www.chachatelier.fr/latexit;
};

LaunchBar = self.installApplication rec {
  name = "LaunchBar";
  version = "6.9.4";
  sourceRoot = "LaunchBar.app";
  src = super.fetchurl {
    url = "https://www.obdev.at/downloads/launchbar/LaunchBar-6.9.4.dmg";
    sha256 = "19k8g2w10qi400rak6894w3lc5j58sq5sfd2r51w9y4fb1wwgg8v";
    # date = 2018-02-04T23:37:26-0800;
  };
  description = ''
    Start with a single keyboard shortcut to access and control every aspect
    of your digital life.
  '';
  homepage = https://www.obdev.at/products/launchbar;
};

OmniGrafflePro_6 = self.installApplication rec {
  name = "OmniGrafflePro";
  appname = "OmniGraffle";
  version = "6.6.2";
  sourceRoot = "OmniGraffle.app";
  src = super.fetchurl {
    url = "https://downloads.omnigroup.com/software/MacOSX/10.10/OmniGraffle-${version}.dmg";
    sha256 = "0a5q1rnajjk4ds59h1mx4rfv8dcja6i4dxnyrl1jgi468rjmmc7h";
    # date = 2018-02-04T22:08:16-0800;
  };
  description = "Professional graphing software for macOS";
  homepage = https://www.omnigroup.com/omnigraffle;
};

OmniOutlinerPro = self.installApplication rec {
  name = "OmniOutlinerPro";
  appname = "OmniOutliner";
  version = "5.2";
  sourceRoot = "OmniOutliner.app";
  src = super.fetchurl {
    url = "https://downloads.omnigroup.com/software/MacOSX/10.12/OmniOutliner-${version}.dmg";
    sha256 = "1b1qi5wbjfr49vyqyrqydlxc3ph4r1akhg2xw8sh4mvlrqh9403x";
    # date = 2018-02-04T22:18:19-0800;
  };
  description = "Professional outlining software for macOS";
  homepage = https://www.omnigroup.com/omnioutliner;
};

OpenZFSonOSX = with super; stdenv.mkDerivation rec {
  name = "OpenZFS-on-OSX";
  version = "1.7.0";
  src = super.fetchurl {
    name = "OpenZFS-${version}.pkg";
    url = "https://openzfsonosx.org/forum/download/file.php?id=98&sid=b403862a792839f9a372eebac59345cf";
    sha256 = "1ii5vf9yvcnfhr2yq7zs695fn4y20kgyb0gg5lgl469kzjwf49lq";
    # date = 2018-02-19T21:38:01-0800;
  };

  buildInputs = [ rsync cpio ];

  unpackPhase = ''
    /usr/bin/xar -xf $src
    cd zfs1013.pkg
  '';

  buildPhase = ''
    cat Payload | gunzip -dc | cpio -i
  '';

  nativeBuildInputs = [ fixDarwinDylibNames ];

  postFixup = ''
    for exe in $(find "$out/bin" "$out/lib" \
                   -type f ! -name '*.la' \
                   \( -executable -o -name '*.dylib' \)); do
      isScript $exe && continue
      for lib in \
          libdiskmgt.1.dylib \
          libnvpair.1.dylib \
          libuutil.1.dylib \
          libzfs.2.dylib \
          libzfs_core.1.dylib \
          libzpool.1.dylib; do
        install_name_tool -change /usr/local/lib/$lib @executable_path/../lib/$lib $exe
      done
    done
  '';

  installPhase = ''
    rsync -av usr/local/ $out/

    mkdir -p $out/etc/zfs/zed.d
    cp etc/zfs/zed.d/zed-functions.sh $out/etc/zfs/zed.d
    cp etc/zfs/zed.d/zed.rc $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/all-syslog.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/checksum-notify.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/checksum-spare.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/config.remove.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/config.sync.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/data-notify.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/io-notify.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/io-spare.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/resilver.finish-notify.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/scrub.finish-notify.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/snapshot.mount.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/zpool.destroy.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/zpool.import.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/zvol.create.sh $out/etc/zfs/zed.d
    ln -s $out/libexec/zfs/zed.d/zvol.remove.sh $out/etc/zfs/zed.d
  '';

  description = "The open source port of OpenZFS on OS X";
  homepage = https://openzfsonosx.org;
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

PhoneView = self.installApplication rec {
  name = "PhoneView";
  version = "2.13.6";
  sourceRoot = "PhoneView Demo/PhoneView Demo.app";
  src = super.fetchurl {
    url = http://downloads.ecamm.com/PhoneView.zip;
    sha256 = "05axjghckm2ggm9jrdb5fy4a1blya2xqy6ri6ay9h8pj8j79kinn";
    # date = 2018-02-04T22:24:51-0800;
  };
  description = ''
    With PhoneView, you can view, save and print all of your iPhone and iPad
    messages, WhatsApp messages, voicemail and other data directly on your
    Mac.
  '';
  homepage = http://www.ecamm.com/mac/phoneview;
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

SageMath = self.installApplication rec {
  name = "SageMath";
  version = "8.1";
  sourceRoot = "SageMath-${version}.app";
  src = super.fetchurl {
    url = "http://mirrors.xmission.com/sage/osx/intel/sage-${version}-OSX_10.12.6-x86_64.app.dmg";
    sha256 = "0cvdp9p4jvv23a8spswb0g9rj1rpcz64qzmfdg9cqww875lm6ydx";
    # date = 2018-02-04T13:08:53-0800;
  };
  description = ''
    SageMath is a free open-source mathematics software system licensed under
    the GPL. It builds on top of many existing open-source packages: NumPy,
    SciPy, matplotlib, Sympy, Maxima, GAP, FLINT, R and many more. Access
    their combined power through a common, Python-based language or directly
    via interfaces or wrappers.
  '';
  homepage = http://www.sagemath.org;
};

Skim = self.installApplication rec {
  name = "Skim";
  version = "1.4.32";
  sourceRoot = "Skim.app";
  src = super.fetchurl {
    name = "Skim-${version}.dmg";
    url = "https://sourceforge.net/projects/skim-app/files/Skim/Skim-${version}/Skim-${version}.dmg/download";
    sha256 = "15j7r328dxhlwdihw9g82pidmwx5lbrqz2xd07g858rx3v3bcf9k";
    # date = 2018-02-04T15:50:51-0800;
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
    # date = 2018-02-04T15:50:51-0800;
  };
  description = ''
    A window management application (replacement for Divvy/SizeUp/ShiftIt)
  '';
  homepage = https://github.com/jigish/slate;
};

Soulver = self.installApplication rec {
  name = "Soulver";
  version = "2.6.2";
  sourceRoot = "Soulver.app";
  src = super.fetchurl {
    name = "soulver-${version}.zip";
    url = "http://www.acqualia.com/files/download.php?product=soulver";
    sha256 = "1bimz497nnfigjp4w04v75bx3ymcss1y4i7c1adcjlxs9w41jlm9";
    # date = 2018-02-04T15:54:54-0800;
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
  version = "3.3.1";
  sourceRoot = "Suspicious Package.app";
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

VirtualII = self.installApplication rec {
  name = "VirtualII";
  appname = "Virtual ][";
  version = "8.1";
  sourceRoot = "Virtual ][.app";
  src = super.fetchurl {
    url = http://www.virtualii.com/VirtualII.dmg;
    sha256 = "0d7023vq8c85f4zypxjhsppdi4q49biqxg16kh1vq5jz7w51pkbm";
    # date = 2018-02-04T22:39:02-0800;
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
  version = "5.0.34.6";
  sourceRoot = "Zotero.app";
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

}
