self: pkgs: rec {

emacs = emacs26;

compileEmacsFiles  = pkgs.callPackage ./emacs/builder.nix;

fetchFromEmacsWiki = pkgs.callPackage ({ fetchurl, name, sha256 }:
  fetchurl {
    inherit sha256;
    url = "https://www.emacswiki.org/emacs/download/" + name;
  });

compileEmacsWikiFile = { name, sha256, buildInputs ? [], patches ? [] }:
  compileEmacsFiles {
    inherit name buildInputs patches;
    src = fetchFromEmacsWiki { name = name; sha256 = sha256; };
  };

compileLocalFile = name: compileEmacsFiles {
  inherit name; src = ./emacs + ("/" + name);
};

myEmacsPackageOverrides = emacs: super: self: with self;
  let withPatches = pkg: patches:
    overrideDerivation pkg (attrs: { inherit patches; }); in

  super.melpaPackages // {

  inherit (pkgs) fetchurl fetchgit fetchFromGitHub;
  inherit (pkgs) stdenv;
  inherit (stdenv) mkDerivation lib;
  inherit (lib) overrideDerivation;


  edit-env        = compileLocalFile "edit-env.el";
  edit-var        = compileLocalFile "edit-var.el";
  ox-extra        = compileLocalFile "ox-extra.el";
  rs-gnus-summary = compileLocalFile "rs-gnus-summary.el";
  supercite       = compileLocalFile "supercite.el";


  company-coq = withPatches melpaPackages.company-coq
    [ ./emacs/patches/company-coq.patch ];

  esh-buf-stack = withPatches melpaPackages.esh-buf-stack
    [ ./emacs/patches/esh-buf-stack.patch ];

  git-link = withPatches melpaPackages.git-link
    [ ./emacs/patches/git-link.patch ];

  haskell-mode = withPatches melpaPackages.haskell-mode
    [ ./emacs/patches/haskell-mode.patch ];

  helm-google = withPatches melpaPackages.helm-google
    [ ./emacs/patches/helm-google.patch ];

  hyperbole = withPatches elpaPackages.hyperbole
    [ ./emacs/patches/hyperbole.patch ];

  magit = withPatches melpaPackages.magit
    [ ./emacs/patches/magit.patch ];

  multi-term = withPatches melpaPackages.multi-term
    [ ./emacs/patches/multi-term.patch ];

  noflet = withPatches melpaPackages.noflet
    [ ./emacs/patches/noflet.patch ];

  org-ref = withPatches melpaPackages.org-ref
    [ ./emacs/patches/org-ref.patch ];

  pass = withPatches melpaPackages.pass
    [ ./emacs/patches/pass.patch ];

  password-store = withPatches melpaPackages.password-store
    [ ./emacs/patches/password-store.patch ];

  swiper = withPatches melpaPackages.swiper
    [ ./emacs/patches/swiper.patch ];


  ascii = compileEmacsWikiFile {
    name = "ascii.el";
    sha256 = "05fjsj5nmc05cmsi0qj914dqdwk8rll1d4dwhn0crw36p2ivql75";
    # date = 2018-01-16T15:05:25-0800;
  };

  backup-each-save = compileEmacsWikiFile {
    name = "backup-each-save.el";
    sha256 = "0b9vvi2m0fdv36wj8mvawl951gjmg3pypg08a8n6rzn3rwg0fwz7";
    # date = 2018-01-16T15:05:29-0800;
  };

  browse-kill-ring-plus = compileEmacsWikiFile {
    name = "browse-kill-ring+.el";
    sha256 = "1s32f70lc1gnllqqfw8zqr5n743rf0yfifqljsl210vnb5zg4zkj";
    # date = 2018-01-16T15:05:32-0800;

    buildInputs = [ browse-kill-ring ];
    patches = [ ./emacs/patches/browse-kill-ring-plus.patch ];
  };

  col-highlight = compileEmacsWikiFile {
    name = "col-highlight.el";
    sha256 = "0na8aimv5j66pzqi4hk2jw5kk00ki99zkxiykwcmjiy3h1r9311k";
    # date = 2018-01-16T15:06:01-0800;

    buildInputs = [ vline ];
  };

  crosshairs = compileEmacsWikiFile {
    name = "crosshairs.el";
    sha256 = "0032v3ry043wzvbacm16liykc362pza1bc46x37b307bvbv12qlg";
    # date = 2018-01-16T15:06:03-0800;

    buildInputs = [ hl-line-plus col-highlight vline ];
  };

  cursor-chg = compileEmacsWikiFile {
    name = "cursor-chg.el";
    sha256 = "1zmwh0z4g6khb04lbgga263pqa51mfvs0wfj3y85j7b08f2lqnqn";
    # date = 2018-01-16T15:06:04-0800;
  };

  erc-highlight-nicknames = compileEmacsWikiFile {
    name = "erc-highlight-nicknames.el";
    sha256 = "01r184q86aha4gs55r2vy3rygq1qnxh1bj9qmlz97b2yh8y17m50";
    # date = 2018-01-16T15:06:10-0800;
  };

  fetchmail-mode = compileEmacsWikiFile {
    name = "fetchmail-mode.el";
    sha256 = "19lqkc35kgzm07xjpb9nrcayg69qyijn159lak0mg45fhnybf4a6";
    # date = 2018-01-16T15:06:12-0800;
  };

  highlight = compileEmacsWikiFile {
    name = "highlight.el";
    sha256 = "1f0lz7giv7f80hi4wvhjc688912pjrhwgm4fc16rqyk8rklywxp9";
    # date = 2018-01-16T15:06:19-0800;
  };

  highlight-cl = compileEmacsWikiFile {
    name = "highlight-cl.el";
    sha256 = "0r3kzs2fsi3kl5gqmsv75dc7lgfl4imrrqhg09ij6kq1ri8gjxjw";
    # date = 2018-01-16T15:06:17-0800;
  };

  hl-line-plus = compileEmacsWikiFile {
    name = "hl-line+.el";
    sha256 = "0crkmjah8i61z6c15sgn2cbpbj8xqfx0py1y84pxkcjh1cj7hx7q";
    # date = 2018-01-16T15:06:21-0800;
  };

  message-x = compileEmacsWikiFile {
      name = "message-x.el";
    sha256 = "05ic97plsysh4nqwdrsl5m9f24m11w24bahj8bxzfdawfima2bkf";
    # date = 2018-01-16T15:06:32-0800;
  };

  mudel = compileEmacsWikiFile {
    name = "mudel.el";
    sha256 = "0z6giw5i3qflxll29k6nbmy71nkadbjjkh465fcqbs2v22643fr9";
    # date = 2018-01-16T15:06:36-0800;
  };

  popup-pos-tip = compileEmacsWikiFile {
    name = "popup-pos-tip.el";
    sha256 = "0dhyzfsl01y61m53iz38a1vcvclr98wamsh0nishw0by1dnlb17x";
    # date = 2018-01-16T15:06:42-0800;

    buildInputs = [ popup pos-tip ];
  };

  popup-ruler = compileEmacsWikiFile {
    name = "popup-ruler.el";
    sha256 = "0fszl969savcibmksfkanaq11d047xbnrfxd84shf9z9z2i3dr43";
    # date = 2018-01-16T15:06:44-0800;
  };

  pp-c-l = compileEmacsWikiFile {
    name = "pp-c-l.el";
    sha256 = "03mhd8lja71163jg6fj4d4hy2dwb1c5j46sn9yq6m9wz413a4pmd";
    # date = 2018-01-16T15:06:46-0800;
  };

  tidy = compileEmacsWikiFile {
    name = "tidy.el";
    sha256 = "0psci55a3angwv45z9i8wz8jw634rxg1xawkrb57m878zcxxddwa";
    # date = 2018-01-16T15:06:52-0800;
  };

  vline = compileEmacsWikiFile {
    name = "vline.el";
    sha256 = "1ys6928fgk8mswa4gv10cxggir8acck27g78cw1z3pdz5gakbgnj";
    # date = 2018-01-16T15:06:55-0800;
  };

  xml-rpc = compileEmacsWikiFile {
    name = "xml-rpc.el";
    sha256 = "0a9n3mj39icfkbsqpcpg9q1d5yz6h3jhay70ngiwsa4264ha4ipa";
    # date = 2018-01-16T15:06:58-0800;
  };

  xray = compileEmacsWikiFile {
    name = "xray.el";
    sha256 = "12pzik5plywil0rz95rqb5qdqwdawkbwhmqab346yizhlp6i4fq6";
    # date = 2018-01-16T15:06:59-0800;
  };


  bytecomp-simplify = compileEmacsFiles {
    name = "bytecomp-simplify.el";
    src = fetchurl {
      url = https://download.tuxfamily.org/user42/bytecomp-simplify.el;
      sha256 = "13cg5nrh0zfyb8rymwlc1lj8mlns27nmj2p7jycl8krwln36g6jr";
      # date = 2018-01-27T17:28:14-0800;
    };
  };

  cldoc = compileEmacsFiles {
    name = "cldoc.el";
    src = fetchurl {
      url = http://homepage1.nifty.com/bmonkey/emacs/elisp/cldoc.el;
      sha256 = "0svv1k7fr4a1syplp0fdfn1as7am0d7g5z8hhl4qhmd5b0hl1pad";
      # date = 2018-01-16T15:05:37-0800;
    };
  };

  # jww (2018-01-16): This is present in melpaPackages, but does not build.
  cmake-mode = compileEmacsFiles {
    name = "cmake-mode.el";
    src = fetchurl {
      url = https://raw.githubusercontent.com/Kitware/CMake/master/Auxiliary/cmake-mode.el;
      sha256 = "11969b7hdvfx2zxhbpcfshdwi5kk2kigg43hli4yacpkhvl7f2qd";
      # date = 2018-01-16T15:05:55-0800;
    };
  };

  jobhours = compileEmacsFiles {
    name = "jobhours";
    src = ~/src/hours;
  };

  nf-procmail-mode = compileEmacsFiles {
    name = "nf-procmail-mode.el";
    src = fetchurl {
      url = http://www.splode.com/~friedman/software/emacs-lisp/src/nf-procmail-mode.el;
      sha256 = "1a7byym62g2rjh2grrqh1g51p05cibp6k83581xyn7fai5f4hxx3";
      # date = 2018-01-16T15:06:37-0800;
    };
  };

  tablegen-mode = compileEmacsFiles {
    name = "tablegen-mode.el";
    src = fetchurl {
      url = https://raw.githubusercontent.com/llvm-mirror/llvm/master/utils/emacs/tablegen-mode.el;
      sha256 = "0vinzlin17ghp2xg0mzxw58jp08fg0jxmq228rd6n017j48b89ck";
      # date = 2018-01-16T15:06:51-0800;
    };
  };


  anki-editor = compileEmacsFiles {
    name = "anki-editor";
    src = fetchFromGitHub {
      owner = "louietan";
      repo = "anki-editor";
      rev = "690121ce582105239f8bf20a9c011b8c6bb1661a";
      sha256 = "168lixn9s3s1p33qw8x6wr5ll6mikkx3316xfsql0bdnz1rkk6cp";
      # date = 2018-01-28T17:29:35+08:00;
    };
  };

  asoc = compileEmacsFiles {
    name = "asoc";
    src = fetchFromGitHub {
      owner = "troyp";
      repo = "asoc.el";
      rev = "4a3309a9f250656da6f4a9d34feedf4f5666b17a";
      sha256 = "1ls4j4fqx33wd2y2fwdh6bagpp04zqhc35p2wy77axmkz9lv5qpv";
      # date = 2017-09-17T22:08:18+10:00;
    };
  };

  bookmark-plus = compileEmacsFiles {
    name = "bookmark-plus";
    src = fetchFromGitHub {
      owner = "emacsmirror";
      repo = "bookmark-plus";
      rev = "954d48092247e9fd461d310fd9fc3c0d545362d5";
      sha256 = "0c9yiwrc6apxrrc8dyfdgs6q2m2l8rd92rwmywci7ivhcpp4cadi";
      # date = 2017-12-04T00:55:55+01:00;
    };
  };

  emacs-load-time = compileEmacsFiles {
    name = "emacs-load-time";
    src = fetchFromGitHub {
      owner = "fniessen";
      repo = "emacs-load-time";
      rev = "9d31686a76e9792bd06e49ff77c662065ded015c";
      sha256 = "0zhrfidcxqfld7y67pysdlcvrprrka9sq8065ygqx5yxjb7mxs32";
      # date = 2014-10-10T16:52:58+02:00;
    };
  };

  erc-yank = compileEmacsFiles {
    name = "erc-yank";
    src = fetchFromGitHub {
      owner = "jwiegley";
      repo = "erc-yank";
      rev = "d4dfcf3a0386c3a4a28f8d4de4ae664f253e817c";
      sha256 = "0sa1qx549wlswa3xnmmpb8a3imny0q8mfvqw8iki5l3sh60rfax9";
      # date = 2017-01-20T15:26:06-08:00;
    };
  };

  feebleline = compileEmacsFiles {
    name = "feebleline";
    src = fetchFromGitHub {
      owner = "tautologyclub";
      repo = "feebleline";
      rev = "00d891603b1d3c786a2f1e56000296c1573c4456";
      sha256 = "1p7jiav16r467k5kpbvwphz7690dczhak0ghcmkj9h4gcbklngs1";
      # date = 2018-01-29T13:25:07+01:00;
    };
  };

  fence-edit = compileEmacsFiles {
    name = "fence-edit";
    src = fetchFromGitHub {
      owner = "aaronbieber";
      repo = "fence-edit.el";
      rev = "93ebdc31d550b0944f6e2d5e6d5e0983d757278e";
      sha256 = "0l07swd1qzn03l22kzl7cl22r3bikfw9i4hsq6xf4kb68zkikfk6";
      # date = 2017-09-25T06:15:49-04:00;
    };
  };

  git-undo = compileEmacsFiles {
    name = "git-undo";
    src = fetchFromGitHub {
      owner = "jwiegley";
      repo = "git-undo-el";
      rev = "852824ab7cb30f5a57361d3e567d78e7864655b1";
      sha256 = "1pc8aaax5qmbl6khb1ixfmr4dhb5dad4qwpd902liqi2fpiy64gl";
      # date = 2017-11-20T16:01:29-08:00;
    };
  };

  gnus-harvest = compileEmacsFiles {
    name = "gnus-harvest";
    src = fetchFromGitHub {
      owner = "jwiegley";
      repo = "gnus-harvest";
      rev = "181ac4a1c2d2b697dd90a1c615bc511e0f196f5d";
      sha256 = "1ilwk8yc2834mxfc37l2qrvljbzjgvcb8ricnd8sa52mvql9dh3r";
      # date = 2014-02-16T23:02:13-06:00;
    };
  };

  indent-shift = compileEmacsFiles {
    name = "indent-shift";
    src = fetchFromGitHub {
      owner = "ryuslash";
      repo = "indent-shift";
      rev = "292993d61d88d80c4a4429aa97856f612e0402b2";
      sha256 = "13shcwpx52cgbh68zqw4yzxccdds532mmkffiz24jc34aridax5z";
      # date = 2014-06-04T02:04:46+02:00;
    };
    patches = [ ./emacs/patches/indent-shift.patch ];
  };

  info-lookmore = compileEmacsFiles {
    name = "info-lookmore";
    src = fetchFromGitHub {
      owner = "emacsmirror";
      repo = "info-lookmore";
      rev = "5e2e62feea2b5149a82365be5580f9e328dd36cc";
      sha256 = "1gfsblgwxszmnx1pf29czvik92ywprvryb57g89zwf31486gjb21";
      # date = 2017-01-20T12:58:03+01:00;
    };
  };

  makefile-runner = compileEmacsFiles {
    name = "makefile-runner";
    src = fetchFromGitHub {
      owner = "danamlund";
      repo = "emacs-makefile-runner";
      rev = "300ba3820aa0536ef4622f78d67ff1730f7e8521";
      sha256 = "14ncli24x6g25krgjhx46bp1hc0x2hgavcl5ssgj2k2mn8zimkmf";
      # date = 2017-07-29T16:05:20+02:00;
    };
  };

  moccur-edit = compileEmacsFiles {
    name = "moccur-edit";
    src = fetchFromGitHub {
      owner = "myuhe";
      repo = "moccur-edit.el";
      rev = "026f5dd4159bd1b68c430ab385757157ba01a361";
      sha256 = "1qikrqs69zqzjpz8bchjrg96bzhj7cbcwkvgsrrx113p420k90zx";
      # date = 2015-03-01T18:04:32+09:00;
    };
    buildInputs = [ color-moccur ];
  };

  org-opml = compileEmacsFiles {
    name = "org-opml";
    src = fetchFromGitHub {
      owner = "edavis";
      repo = "org-opml";
      rev = "d9019be8653a4406eacf15a06afb8b162d2625a6";
      sha256 = "1nj0ccjyj4yn5b77m9p1asgx41fpgpypsxfnqwhqwgxywhap00w1";
      # date = 2017-06-10T11:37:25-07:00;
    };
  };

  ovpn-mode = compileEmacsFiles {
    name = "ovpn-mode";
    src = fetchFromGitHub {
      owner = "collarchoke";
      repo = "ovpn-mode";
      rev = "79aa879dcad05e89e7fd32e2cbef78878ddfd857";
      sha256 = "0dsgk1lycs99xkqkzlkrs7yxjnw3z39r4r7mm8ghqqwdk3r67fw7";
      # date = "2018-01-24T09:33:00-05:00";
    };
  };

  ox-texinfo-plus = compileEmacsFiles {
    name = "ox-texinfo-plus";
    src = fetchFromGitHub {
      owner = "tarsius";
      repo = "ox-texinfo-plus";
      rev = "d3c57f2d60283aa1667d93785fd66765c3769189";
      sha256 = "13brkf7gqcyg7imb92naa8205m0c3wvrv2pssbmbzw9gy7yi421q";
      # date = 2017-10-06T12:55:55+02:00;
    };
  };

  per-window-point = compileEmacsFiles {
    name = "per-window-point";
    src = fetchFromGitHub {
      owner = "alpaker";
      repo = "Per-Window-Point";
      rev = "bd780d0e76814280bc055560e04bc6e606afa69a";
      sha256 = "1kkm957a89fszbikjm1w6dwwnklxn2vwzk3jk9bqzhkpacsqcr16";
      # date = 2013-08-07T09:14:20-04:00;
    };
  };

  peval = compileEmacsFiles {
    name = "peval";
    src = fetchFromGitHub {
      owner = "Wilfred";
      repo = "peval";
      rev = "36af7344121d0d7826ae2516dc831fd90c9909ef";
      sha256 = "1xwfbmm08sbf3fcc7viaysl6rsg4dx3wlmyrv0cfncscxg8x1f1c";
      # date = 2017-12-19T22:30:41+00:00;
    };
    buildInputs = [ dash ];
  };

  sdcv-mode = compileEmacsFiles {
    name = "sdcv-mode";
    src = fetchFromGitHub {
      owner = "gucong";
      repo = "emacs-sdcv";
      rev = "c51569ebf3fd1f8c02c33c289d229996bf2ff186";
      sha256 = "0qkvapiaprv9p5zrzr7xfy2prwjnhc3rq3r21zcppcb5habbvy8q";
      # date = 2012-01-28T14:08:32-06:00;
    };
  };

  sky-color-clock = compileEmacsFiles {
    name = "sky-color-clock";
    src = fetchFromGitHub {
      owner = "zk-phi";
      repo = "sky-color-clock";
      rev = "d9e4b65d8b4fd5d74619c2a5c41a9d0c72ccdbd2";
      sha256 = "0xfc51h8bjl1m591naxdrq2fz7hflzx4zkmiixifhq699ynza71k";
      # date = 2018-01-24T17:07:38+09:00;
    };
    patches = [ ./emacs/patches/sky-color-clock.patch ];
  };

  stopwatch = compileEmacsFiles {
    name = "stopwatch";
    src = fetchFromGitHub {
      owner = "lalopmak";
      repo = "stopwatch";
      rev = "107bdbafdc11128112169b41cf001384a203408a";
      sha256 = "05k16z4w552rspdngjs5c74ng010zmdiwqjn0iahk05l5apx6wd8";
      # date = 2013-08-11T19:22:20-05:00;
    };
  };

  sunrise-commander = compileEmacsFiles {
    name = "sunrise-commander";
    src = fetchFromGitHub {
      owner = "escherdragon";
      repo = "sunrise-commander";
      rev = "cf8305a149a321d028858057e7a7c92f0038a06a";
      sha256 = "1jkdrs3rpn520daskvr7kdm29zwb8rrbbcaqgvai2rcj3dbqa8f8";
      # date = 2017-12-17T20:09:39+01:00;
    };
  };

  word-count-mode = compileEmacsFiles {
    name = "word-count-mode";
    src = fetchFromGitHub {
      owner = "tomaszskutnik";
      repo = "word-count-mode";
      rev = "6267c98e0d9a3951e667da9bace5aaf5033f4906";
      sha256 = "1pvwy6dm6pwm0d8dd4l1d5rqk31w39h5n4wxqmq2ipwnxrlxp0nh";
      # date = 2015-07-16T22:37:17+02:00;
    };
  };

  yari-with-buttons = compileEmacsFiles {
    name = "yari-with-buttons";
    src = fetchFromGitHub {
      owner = "pedz";
      repo = "yari-with-buttons";
      rev = "9d5bbf59f6ea8dece493cbe609d9c510698eee41";
      sha256 = "1ipk881150152hzhha37sp8162lazw08rkkiahcr5s85f177dkih";
      # date = 2013-11-28T19:05:23-06:00;
    };
  };


  doxymacs = mkDerivation rec {
    name = "emacs-doxymacs-${version}";
    version = "2017-12-10";

    src = fetchgit {
      url = git://git.code.sf.net/p/doxymacs/code.git;
      rev = "914d5cc98129d224e15bd68c39ec8836830b08a2";
      sha256 = "1xqjga5pphcfgqzj9lxfkm50sc1qag1idf54lpa23z81wrxq9dy3";
      # date = 2010-03-07T21:45:41+00:00;
    };

    buildInputs = [ emacs ] ++ (with pkgs; [ texinfo perl which ]);

    meta = {
      description = "Doxymacs is Doxygen + {X}Emacs";
      longDescription = ''
        The purpose of the doxymacs project is to create a LISP package that
        will make using Doxygen from within {X}Emacs easier.
      '';
      homepage = http://doxymacs.sourceforge.net/;
      license = lib.licenses.gpl2Plus;
      platforms = lib.platforms.unix;
    };
  };

  elfeed = melpaBuild {
    pname = "elfeed";
    version = "20180127.1742";
    src = fetchFromGitHub {
      owner = "skeeto";
      repo = "elfeed";
      rev = "e2b0e255fc3a3cb3e9d69c05df3b8e9d7ca70e86";
      sha256 = "1sq2w40ac8nc6pvifl0r5ri255jcd237x5rxfliwd2wdwqhk9izd";
      # date = 2018-01-27T17:42:53-05:00;
    };
    recipeFile = fetchurl {
      url = "https://raw.githubusercontent.com/milkypostman/melpa/407ae027fcec444622c2a822074b95996df9e6af/recipes/elfeed";
      sha256 = "1psga7fcjk2b8xjg10fndp9l0ib72l5ggf43gxp62i4lxixzv8f9";
      name = "elfeed";
    };
    packageRequires = [ emacs ];
    meta = {
      homepage = "https://melpa.org/#/elfeed";
      license = lib.licenses.free;
    };
  };

  org = mkDerivation rec {
    name = "emacs-org-${version}";
    version = "20160421";
    src = fetchFromGitHub {
      owner  = "jwiegley";
      repo   = "org-mode";
      rev    = "db5257389231bd49e92e2bc66713ac71b0435eec";
      sha256 = "073cmwgxga14r4ykbgp8w0gjp1wqajmlk6qv9qfnrafgpxic366m";
    };
    preBuild = ''
      rm -f contrib/lisp/org-jira.el
      makeFlagsArray=(
        prefix="$out/share"
        ORG_ADD_CONTRIB="org* ox*"
      );
    '';
    preInstall = ''
      perl -i -pe "s%/usr/share%$out%;" local.mk
    '';
    buildInputs = [ emacs ] ++ (with pkgs; [ texinfo perl which ]);
    meta = {
      homepage = "https://elpa.gnu.org/packages/org.html";
      license = lib.licenses.free;
    };
  };

  proof-general = with pkgs;
    let texinfo = texinfo4 ;
        texLive = texlive.combine {
          inherit (texlive) scheme-basic cm-super ec;
        }; in mkDerivation rec {
    name = "emacs-proof-general-${version}";
    version = "2018-01-16";

    src = fetchFromGitHub {
      owner = "ProofGeneral";
      repo = "PG";
      rev = "945cada601c5729edd16fcc989a3969c8b34d20a";
      sha256 = "1zjmbhq6c8g8b93nnsvr5pxx6mlcndb0fz152b2h80vfh9663cn8";
      # date = 2018-01-30T14:28:25+01:00;
    };

    buildInputs = [ emacs ] ++ (with pkgs; [ texinfo perl which ]);

    prePatch =
      '' sed -i "Makefile" \
             -e "s|^\(\(DEST_\)\?PREFIX\)=.*$|\1=$out|g ; \
                 s|/sbin/install-info|install-info|g"
         sed -i '94d' doc/PG-adapting.texi
         sed -i '96d' doc/ProofGeneral.texi
      '';

    meta = {
      description = "Proof General, an Emacs front-end for proof assistants";
      longDescription = ''
        Proof General is a generic front-end for proof assistants (also known as
        interactive theorem provers), based on the customizable text editor Emacs.
      '';
      homepage = http://proofgeneral.inf.ed.ac.uk;
      license = lib.licenses.gpl2Plus;
      platforms = lib.platforms.unix;
    };
  };

  use-package = melpaBuild {
    pname = "use-package";
    version = "20180127.1411";
    src = ~/src/dot-emacs/lisp/use-package;
    recipeFile = fetchurl {
      url = "https://raw.githubusercontent.com/milkypostman/melpa/51a19a251c879a566d4ae451d94fcb35e38a478b/recipes/use-package";
      sha256 = "0d0zpgxhj6crsdi9sfy30fn3is036apm1kz8fhjg1yzdapf1jdyp";
      name = "use-package";
    };
    packageRequires = [ bind-key emacs ];
    meta = {
      homepage = "https://melpa.org/#/use-package";
      license = lib.licenses.free;
    };
  };
};

emacs26 = with pkgs; stdenv.lib.overrideDerivation
  (emacs25.override { srcRepo = true; }) (attrs: rec {
  name = "emacs-${version}${versionModifier}";
  version = "26.0";
  versionModifier = ".90";

  buildInputs = emacs25.buildInputs ++ [ git ];

  patches = lib.optionals stdenv.isDarwin
    [ ./emacs/patches/at-fdcwd.patch
      ./emacs/patches/emacs-26.patch ];

  CFLAGS = "-Ofast -momit-leaf-frame-pointer";

  src = fetchgit {
    url = https://git.savannah.gnu.org/git/emacs.git;
    rev = "8d4500087f547e203cfba03f61dcbe641bf650de";
    sha256 = "1zk9xm01v4chnxf9ns9c3kx2jal3lj88hadv5vp0zb8xr9vz4f31";
  };

  postPatch = ''
    rm -fr .git
  '';

  postInstall = ''
    mkdir -p $out/share/emacs/site-lisp
    cp ${./emacs/site-start.el} $out/share/emacs/site-lisp/site-start.el
    $out/bin/emacs --batch -f batch-byte-compile $out/share/emacs/site-lisp/site-start.el

    rm -rf $out/var
    rm -rf $out/share/emacs/${version}/site-lisp

    for srcdir in src lisp lwlib ; do
      dstdir=$out/share/emacs/${version}/$srcdir
      mkdir -p $dstdir
      find $srcdir -name "*.[chm]" -exec cp {} $dstdir \;
      cp $srcdir/TAGS $dstdir
      echo '((nil . ((tags-file-name . "TAGS"))))' > $dstdir/.dir-locals.el
    done
  '' + lib.optionalString stdenv.isDarwin ''
    mkdir -p $out/Applications
    mv nextstep/Emacs.app $out/Applications
  '';
});

emacs26debug = pkgs.stdenv.lib.overrideDerivation emacs26 (attrs: rec {
  name = "emacs-26.0.90-debug";
  doCheck = true;
  CFLAGS = "-O0 -g3";
  configureFlags = [ "--with-modules" ] ++
   [ "--with-ns" "--disable-ns-self-contained"
     "--enable-checking=yes,glyphs"
     "--enable-check-lisp-object-type" ];
});

emacs26PackagesNg = pkgs.emacsPackagesNgGen emacs26;
emacsPackagesNg = emacs26PackagesNg;

emacsHEAD = with pkgs; stdenv.lib.overrideDerivation
  (emacs25.override { srcRepo = true; }) (attrs: rec {
  name = "emacs-${version}${versionModifier}";
  version = "27.0";
  versionModifier = ".50";

  appName = "ERC";
  bundleName = "nextstep/ERC.app";
  iconFile = ./emacs/Chat.icns;

  buildInputs = emacs25.buildInputs ++ [ git ];

  patches = lib.optionals stdenv.isDarwin
    [ ./emacs/patches/at-fdcwd.patch
      ./emacs/patches/emacs-26.patch ];

  CFLAGS = "-O0 -g3";

  configureFlags = [ "--with-modules" ] ++
   [ "--with-ns" "--disable-ns-self-contained"
     "--enable-checking=yes,glyphs"
     "--enable-check-lisp-object-type" ];

  src = fetchgit {
    url = https://git.savannah.gnu.org/git/emacs.git;
    rev = "614e9b322ec08cf6549cd4db34e1dc75149e6b31";
    sha256 = "0pbqn33hkwwvw1qrwh0nxn77rj2ryrb1yfbs9sm6j2x9avbfiyha";
  };

  postPatch = ''
    sed -i 's|/usr/share/locale|${gettext}/share/locale|g' \
      lisp/international/mule-cmds.el
    sed -i 's|nextstep/Emacs\.app|${bundleName}|' configure.ac
    sed -i 's|>Emacs<|>${appName}<|' nextstep/templates/Info.plist.in
    sed -i 's|Emacs\.app|${appName}.app|' nextstep/templates/Info.plist.in
    sed -i 's|org\.gnu\.Emacs|org.gnu.${appName}|' nextstep/templates/Info.plist.in
    sed -i 's|Emacs @version@|${appName} @version@|' nextstep/templates/Info.plist.in
    sed -i 's|EmacsApp|${appName}App|' nextstep/templates/Info.plist.in
    if [ -n "${iconFile}" ]; then
      sed -i 's|Emacs\.icns|${appName}.icns|' nextstep/templates/Info.plist.in
    fi
    sed -i 's|Name=Emacs|Name=${appName}|' nextstep/templates/Emacs.desktop.in
    sed -i 's|Emacs\.app|${appName}.app|' nextstep/templates/Emacs.desktop.in
    sed -i 's|"Emacs|"${appName}|' nextstep/templates/InfoPlist.strings.in
    rm -fr .git
    sh autogen.sh
  '';

  postInstall = ''
    mkdir -p $out/share/emacs/site-lisp
    cp ${./emacs/site-start.el} $out/share/emacs/site-lisp/site-start.el
    $out/bin/emacs --batch -f batch-byte-compile $out/share/emacs/site-lisp/site-start.el

    rm -rf $out/var
    rm -rf $out/share/emacs/${version}/site-lisp

    for srcdir in src lisp lwlib ; do
      dstdir=$out/share/emacs/${version}/$srcdir
      mkdir -p $dstdir
      find $srcdir -name "*.[chm]" -exec cp {} $dstdir \;
      cp $srcdir/TAGS $dstdir
      echo '((nil . ((tags-file-name . "TAGS"))))' > $dstdir/.dir-locals.el
    done

    mkdir -p $out/Applications
    if [ "${appName}" != "Emacs" ]; then
        mv ${bundleName}/Contents/MacOS/Emacs ${bundleName}/Contents/MacOS/${appName}
    fi
    if [ -n "${iconFile}" ]; then
      cp "${iconFile}" ${bundleName}/Contents/Resources/${appName}.icns
    fi
    mv ${bundleName} $out/Applications
  '';
});

emacsHEADPackagesNg = pkgs.emacsPackagesNgGen emacsHEAD;

customEmacsHEADPackages =
  emacsHEADPackagesNg.overrideScope (myEmacsPackageOverrides emacsHEAD);

emacsHEAD_is_ERC = epkgs:
  pkgs.stdenv.lib.overrideDerivation epkgs (attrs: {
    installPhase = attrs.installPhase + ''
      if [ -d "$emacs/Applications/ERC.app" ]; then
        mkdir -p $out/Applications/ERC.app/Contents/MacOS
        cp -r $emacs/Applications/ERC.app/Contents/Info.plist \
              $emacs/Applications/ERC.app/Contents/PkgInfo \
              $emacs/Applications/ERC.app/Contents/Resources \
              $out/Applications/ERC.app/Contents
        makeWrapper $emacs/Applications/ERC.app/Contents/MacOS/ERC \
                    $out/Applications/ERC.app/Contents/MacOS/ERC \
                    --suffix EMACSLOADPATH ":" "$deps/share/emacs/site-lisp:"
      fi
    '';
  });

emacsHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "emacsHEAD";
  buildInputs = [
    (emacsHEAD_is_ERC
       (customEmacsHEADPackages.emacsWithPackages myPkgs))
  ];
};

customEmacs26Packages =
  emacs26PackagesNg.overrideScope (myEmacsPackageOverrides emacs26);

emacs26Env = myPkgs: pkgs.myEnvFun {
  name = "emacs26";
  buildInputs = [ (customEmacs26Packages.emacsWithPackages myPkgs) ];
};

customEmacs26DebugPackages =
  emacs26PackagesNg.overrideScope (myEmacsPackageOverrides emacs26debug);

emacs26DebugEnv = myPkgs: pkgs.myEnvFun {
  name = "emacs26debug";
  buildInputs = [ (customEmacs26DebugPackages.emacsWithPackages myPkgs) ];
};

emacs25Env = myPkgs: pkgs.myEnvFun {
  name = "emacs25";
  buildInputs = [ pkgs.emacs25 ];
};

}
