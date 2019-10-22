self: pkgs:

let
  myEmacsPackageOverrides = self: super:
    let
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub stdenv;
      inherit (stdenv) lib mkDerivation;

      withPatches = pkg: patches:
        lib.overrideDerivation pkg (attrs: { inherit patches; });

      compileEmacsFiles = pkgs.callPackage ./emacs/builder.nix;

      addBuildInputs = pkg: inputs: pkg.overrideAttrs (attrs: {
        buildInputs = attrs.buildInputs ++ inputs;
      });

      compileLocalFile = name: compileEmacsFiles {
        inherit name;
        src = ./emacs + ("/" + name);
      };

      fetchFromEmacsWiki = pkgs.callPackage ({ fetchurl, name, sha256 }:
        fetchurl {
          inherit sha256;
          url = "https://www.emacswiki.org/emacs/download/" + name;
        });

      compileEmacsWikiFile = { name, sha256, buildInputs ? [], patches ? [] }:
        compileEmacsFiles {
          inherit name buildInputs patches;
          src = fetchFromEmacsWiki { inherit name sha256; };
        };

    in {

    edit-env        = compileLocalFile "edit-env.el";
    edit-var        = compileLocalFile "edit-var.el";
    ox-extra        = compileLocalFile "ox-extra.el";
    rs-gnus-summary = compileLocalFile "rs-gnus-summary.el";
    supercite       = compileLocalFile "supercite.el";


    magit-annex      = addBuildInputs super.magit-annex        [ pkgs.git ];
    magit-filenotify = addBuildInputs super.magit-filenotify   [ pkgs.git ];
    magit-gitflow    = addBuildInputs super.magit-gitflow      [ pkgs.git ];
    magit-imerge     = addBuildInputs super.magit-imerge       [ pkgs.git ];
    magit-lfs        = addBuildInputs super.magit-lfs          [ pkgs.git ];
    magit-tbdiff     = addBuildInputs super.magit-tbdiff       [ pkgs.git ];
    orgit            = addBuildInputs super.orgit              [ pkgs.git ];


    company-coq   = withPatches super.company-coq   [ ./emacs/patches/company-coq.patch ];
    esh-buf-stack = withPatches super.esh-buf-stack [ ./emacs/patches/esh-buf-stack.patch ];
    helm-google   = withPatches super.helm-google   [ ./emacs/patches/helm-google.patch ];
    magit         = withPatches super.magit         [ ./emacs/patches/magit.patch ];
    noflet        = withPatches super.noflet        [ ./emacs/patches/noflet.patch ];
    org-ref       = withPatches super.org-ref       [ ./emacs/patches/org-ref.patch ];
    pass          = withPatches super.pass          [ ./emacs/patches/pass.patch ];


    ascii = compileEmacsWikiFile {
      name = "ascii.el";
      sha256 = "1ijpnk334fbah94vm7dkcd2w4zcb0l7yn4nr9rwgpr2l25llnr0f";
      # date = 2019-10-16T16:51:27-0700;
    };

    backup-each-save = compileEmacsWikiFile {
      name = "backup-each-save.el";
      sha256 = "0b9vvi2m0fdv36wj8mvawl951gjmg3pypg08a8n6rzn3rwg0fwz7";
      # date = 2019-04-03T08:43:18-0700;
    };

    browse-kill-ring-plus = compileEmacsWikiFile {
      name = "browse-kill-ring+.el";
      sha256 = "14118rimjsps94ilhi0i9mwx7l69ilbidgqfkfrm5c9m59rki2gq";
      # date = 2019-04-03T08:43:20-0700;

      buildInputs = [ self.browse-kill-ring ];
      patches = [ ./emacs/patches/browse-kill-ring-plus.patch ];
    };

    col-highlight = compileEmacsWikiFile {
      name = "col-highlight.el";
      sha256 = "0na8aimv5j66pzqi4hk2jw5kk00ki99zkxiykwcmjiy3h1r9311k";
      # date = 2019-04-03T08:43:22-0700;

      buildInputs = [ self.vline ];
    };

    crosshairs = compileEmacsWikiFile {
      name = "crosshairs.el";
      sha256 = "0032v3ry043wzvbacm16liykc362pza1bc46x37b307bvbv12qlg";
      # date = 2019-04-03T08:43:25-0700;

      buildInputs = [ self.hl-line-plus self.col-highlight self.vline ];
    };

    cursor-chg = compileEmacsWikiFile {
      name = "cursor-chg.el";
      sha256 = "1zmwh0z4g6khb04lbgga263pqa51mfvs0wfj3y85j7b08f2lqnqn";
      # date = 2019-04-03T08:43:27-0700;
    };

    erc-highlight-nicknames = compileEmacsWikiFile {
      name = "erc-highlight-nicknames.el";
      sha256 = "01r184q86aha4gs55r2vy3rygq1qnxh1bj9qmlz97b2yh8y17m50";
      # date = 2019-04-03T08:43:29-0700;
    };

    fetchmail-mode = compileEmacsWikiFile {
      name = "fetchmail-mode.el";
      sha256 = "19lqkc35kgzm07xjpb9nrcayg69qyijn159lak0mg45fhnybf4a6";
      # date = 2019-04-03T08:43:31-0700;
    };

    hexrgb = compileEmacsWikiFile {
      name = "hexrgb.el";
      sha256 = "18hb8brf7x92aidjfgczxangri6rkqq4x5d06lh41193f97rslm8";
      # date = 2019-04-03T08:43:33-0700;
    };

    highlight = compileEmacsWikiFile {
      name = "highlight.el";
      sha256 = "1a94xsjd98qdl06vmq8mi7rsygbngh97iqk5hbibxhbpwjz0njfw";
      # date = 2019-08-21T17:38:13-0700;
    };

    highlight-cl = compileEmacsWikiFile {
      name = "highlight-cl.el";
      sha256 = "0r3kzs2fsi3kl5gqmsv75dc7lgfl4imrrqhg09ij6kq1ri8gjxjw";
      # date = 2019-08-21T17:38:10-0700;
    };

    hl-line-plus = compileEmacsWikiFile {
      name = "hl-line+.el";
      sha256 = "0crkmjah8i61z6c15sgn2cbpbj8xqfx0py1y84pxkcjh1cj7hx7q";
      # date = 2019-04-03T08:43:37-0700;
    };

    message-x = compileEmacsWikiFile {
      name = "message-x.el";
      sha256 = "05ic97plsysh4nqwdrsl5m9f24m11w24bahj8bxzfdawfima2bkf";
      # date = 2019-04-03T08:43:39-0700;
    };

    palette = compileEmacsWikiFile {
      name = "palette.el";
      sha256 = "149y6bmn0njgq632m9zdnaaw7wrvxvfqndpqlgcizn6dwzixiih6";
      # date = 2019-04-03T08:43:41-0700;

      buildInputs = [ self.hexrgb ];
    };

    popup-pos-tip = compileEmacsWikiFile {
      name = "popup-pos-tip.el";
      sha256 = "0dhyzfsl01y61m53iz38a1vcvclr98wamsh0nishw0by1dnlb17x";
      # date = 2019-04-03T08:51:23-0700;

      buildInputs = [ self.popup self.pos-tip ];
    };

    popup-ruler = compileEmacsWikiFile {
      name = "popup-ruler.el";
      sha256 = "0fszl969savcibmksfkanaq11d047xbnrfxd84shf9z9z2i3dr43";
      # date = 2019-04-03T08:51:26-0700;
    };

    pp-c-l = compileEmacsWikiFile {
      name = "pp-c-l.el";
      sha256 = "03mhd8lja71163jg6fj4d4hy2dwb1c5j46sn9yq6m9wz413a4pmd";
      # date = 2019-04-03T08:51:27-0700;
    };

    tidy = compileEmacsWikiFile {
      name = "tidy.el";
      sha256 = "0psci55a3angwv45z9i8wz8jw634rxg1xawkrb57m878zcxxddwa";
      # date = 2019-04-03T08:51:29-0700;
    };

    vline = compileEmacsWikiFile {
      name = "vline.el";
      sha256 = "1ys6928fgk8mswa4gv10cxggir8acck27g78cw1z3pdz5gakbgnj";
      # date = 2019-04-03T08:51:30-0700;
    };

    xml-rpc = compileEmacsWikiFile {
      name = "xml-rpc.el";
      sha256 = "1lmmzd9vpvybva642558wfm6nv21x7c0qrm6487r31l3k18lz3nd";
      # date = 2019-04-03T08:51:31-0700;
    };

    xray = compileEmacsWikiFile {
      name = "xray.el";
      sha256 = "1s25z9iiwpm1sp3yj9mniw4dq7dn0krk4678bgqh464k5yvn6lyk";
      # date = 2019-10-16T16:58:04-0700;
    };

    yaoddmuse = compileEmacsWikiFile {
      name = "yaoddmuse.el";
      sha256 = "0h3s3mdfz0czgz1cj415k170g7mbbqmsinw0xr7qmk050i154iis";
      # date = 2019-04-03T08:51:34-0700;
    };


    bytecomp-simplify = compileEmacsFiles {
      name = "bytecomp-simplify.el";
      src = fetchurl {
        url = https://download.tuxfamily.org/user42/bytecomp-simplify.el;
        sha256 = "1yq0wqgva8yidyd46cqag0ds0cyzl7q8rpd2cmksp68k4zlsxwyv";
        # date = 2019-06-25T12:42:17-0700;
      };
    };

    # jww (2018-01-16): This is present in melpaPackages, but does not build.
    cmake-mode = compileEmacsFiles {
      name = "cmake-mode.el";
      src = fetchurl {
        url = https://raw.githubusercontent.com/Kitware/CMake/master/Auxiliary/cmake-mode.el;
        sha256 = "1a0dsw8cs29v6j7iji24d9k089f6q5wxjy5a0p1vfflfwa6i20ch";
        # date = 2019-08-21T17:37:59-0700;
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
        # date = 2019-04-03T08:51:58-0700;
      };
    };

    tablegen-mode = compileEmacsFiles {
      name = "tablegen-mode.el";
      src = fetchurl {
        url = https://raw.githubusercontent.com/llvm-mirror/llvm/master/utils/emacs/tablegen-mode.el;
        sha256 = "0dy0diiqfz91blrkpbfxc5ky0l7ghkqi72ah7sh9jkrqa8ss7isy";
        # date = 2019-10-16T16:55:59-0700;
      };
    };


    anki-editor = compileEmacsFiles {
      name = "anki-editor";
      src = fetchFromGitHub {
        owner = "louietan";
        repo = "anki-editor";
        rev = "084ffad14fa700ad1ba95d8cbfe4a8f6052e2408";
        sha256 = "0zjd5yid333shvjm4zy3p7zdpa09xcl96gc4wvi2paxjad6iqhwz";
        # date = 2019-09-22T20:23:39+08:00;
      };
      buildInputs = with self; [ dash request ];
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
        rev = "efd593bf14d8f175e6bafad7101713507818c75d";
        sha256 = "1xm4snfgiaajziqsj9k4yg55zvrfg033fipx5awwa0j1zxy90gvd";
        # date = 2019-08-21T20:17:40+02:00;
      };
    };

    deadgrep = compileEmacsFiles {
      name = "deadgrep";
      src = fetchFromGitHub {
        owner = "Wilfred";
        repo = "deadgrep";
        rev = "329119c65126f7917d3910bc584f4191ba8f21ac";
        sha256 = "0fxf7gq9sjfkgpdfqx10w3l3nd4rwa8kv9plyxk1fqacb3s5m6ai";
        # date = 2019-08-07T22:25:18+01:00;
      };
      buildInputs = with self; [ s dash spinner ];
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
        rev = "b2f2db25cac77817bf0c49ea2cea6383556faea0";
        sha256 = "0f2nynx9sib29qi3zkfkgxlcfrwz607pgg6qvvk4nnads033p1yn";
        # date = 2019-08-22T16:01:05+02:00;
      };
    };

    fence-edit = compileEmacsFiles {
      name = "fence-edit";
      src = fetchFromGitHub {
        owner = "aaronbieber";
        repo = "fence-edit.el";
        rev = "d05f82fb99f787b24cdf5f77dc90fab0d6e00761";
        sha256 = "0sdmc89ycrxnfj25dva86sqa8x5rjfs6jg7gvpwrvgq2126hzqvh";
        # date = 2019-04-03T06:20:48-04:00;
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

    github-review = compileEmacsFiles {
      name = "github-review";
      src = fetchFromGitHub {
        owner = "charignon";
        repo = "github-review";
        rev = "a13a3b4f1b6114a32af843971a145ab880f51232";
        sha256 = "0injfpxzgfhmqalba845j5l5cdcxxqz43knhxwinf36g52nfabl0";
        # date = 2019-08-30T09:39:32-07:00;
      };
      buildInputs = with self; [ ghub dash graphql treepy s ];
    };

    ghub-plus = compileEmacsFiles {
      name = "ghub-plus";
      src = fetchFromGitHub {
        owner = "vermiculus";
        repo = "ghub-plus";
        rev = "51ebffe549286b3c0b0565a373f44f4d64fc57af";
        sha256 = "11fr6ri95a9wkc0mqrkhjxz1fm2cb52151fc88k73l93mggib3ak";
        # date = 2018-11-12T18:32:52-06:00;
      };
      buildInputs = with self; [ ghub apiwrap dash graphql treepy ];
    };

    gnus-harvest = compileEmacsFiles {
      name = "gnus-harvest";
      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "gnus-harvest";
        rev = "feda071a87b799bd5d23cacde3ee71f0b166e75d";
        sha256 = "08zb7vc3v3wdxkzgi902vlc5ybfvm8fxrvm5drnwfsjj9873pbcb";
        # date = 2018-02-08T11:20:21-08:00;
      };
    };

    goto-line-preview = compileEmacsFiles {
      name = "goto-line-preview";
      src = fetchFromGitHub {
        owner = "jcs090218";
        repo = "goto-line-preview";
        rev = "772fb942777a321b4698add1b94cff157f23a93b";
        sha256 = "16zil8kjv7lfmy11g88p1cm24j9db319fgkwzsgf2vzp1m15l0pc";
        # date = 2019-03-08T15:38:36+08:00;
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

    initsplit = compileEmacsFiles {
      name = "initsplit";
      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "initsplit";
        rev = "e488e8f95661a8daf9c66241ce58bb6650d91751";
        sha256 = "1qvkxpxdv0n9qlzigvi25iw485824pgbpb10lwhh8bs2074dvrgq";
        # date = 2015-03-21T23:29:07-05:00;
      };
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

    ivy-compile = compileEmacsFiles {
      name = "ivy-compile.el";
      src = fetchurl {
        url = https://bitbucket.org/holgerschurig/emacsconf/raw/74d428aa2f9be88b14a503f6c3a816ae7cd13644/elisp/ivy-compile.el;
        sha256 = "0igi5p9s6w9yqaxirl286ms9zxad1njw0c6q1b7nry0mh12f7327";
        # date = 2019-04-03T08:52:31-0700;
      };
      buildInputs = with self; [ ivy ];
    };

    ivy-explorer = compileEmacsFiles {
      name = "ivy-explorer";
      src = fetchFromGitHub {
        owner = "clemera";
        repo = "ivy-explorer";
        rev = "a413966cfbcecacc082d99297fa1abde0c10d3f3";
        sha256 = "1720g8i6jq56myv8m9pnr0ab7wagsflm0jgkg7cl3av7zc90zq8r";
        # date = 2019-09-09T21:21:25+02:00;
      };
      buildInputs = with self; [ ivy ];
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

    magit-todos = compileEmacsFiles {
      name = "magit-todos";
      src = fetchFromGitHub {
        owner = "alphapapa";
        repo = "magit-todos";
        rev = "a80dace2bf8bf3e697e3e8421189996adcecc900";
        sha256 = "0qwzag9js6qy98m7c8gmaskg4qc82sf0aihcs5vcxdf8rgia2j9q";
        # date = 2019-09-07T08:21:17-05:00;
      };
      buildInputs = with self; [
        magit magit-popup a anaphora dash f s hl-todo kv with-editor git-commit
        ghub graphql treepy
      ];
    };

    mmm-mode = compileEmacsFiles {
      name = "mmm-mode";
      src = fetchFromGitHub {
        owner = "purcell";
        repo = "mmm-mode";
        rev = "ff0b214f27d5dddeb856acb4216e77a864dcc0b2";
        sha256 = "0lxd55yhz0ag7v1ydff55bg4h8snq5lbk8cjwxqpyq6gh4v7md1h";
        # date = 2018-06-21T16:19:14+03:00;
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
      buildInputs = [ self.color-moccur ];
    };

    nix-mode = compileEmacsFiles {
      name = "nix-mode";
      src = fetchFromGitHub {
        owner = "NixOS";
        repo = "nix-mode";
        rev = "5b5961780f3b1c1b62453d2087f775298980f10d";
        sha256 = "0lyf9vp6sivy321z8l8a2yf99kj5g15p6ly3f8gkyaf6dcq3jgnc";
        # date = 2019-09-04T10:40:40-04:00;
      };
      buildInputs = with self; [ company json-mode mmm-mode json-snatcher json-reformat ];
    };

    org-mind-map = compileEmacsFiles {
      name = "org-mind-map";
      src = fetchFromGitHub {
        owner = "theodorewiles";
        repo = "org-mind-map";
        rev = "16a8aac5462c01c4e7b6b7915381fde42fd3caf6";
        sha256 = "0ipkmws7r8dk2p65m9jri90s8pgxhzidz7g2fmh7d6cz97jbk3v7";
        # date = 2018-09-25T07:13:25-04:00;
      };
      buildInputs = [ self.dash ];
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

    org-pdftools = compileEmacsFiles {
      name = "org-pdftools";
      src = fetchFromGitHub {
        owner = "fuxialexander";
        repo = "org-pdftools";
        rev = "3ca91085290fc3d0f3886c3a3145deea760055b8";
        sha256 = "06fnzs09y57b5cgznlin8y88rcd1a82xn35mazwf8ivxn0lhp2z2";
        # date = 2019-08-30T18:22:51+08:00;
      };
      buildInputs = with self; [ org org-noter pdf-tools tablist ];
    };

    org-rich-yank = compileEmacsFiles {
      name = "org-rich-yank";
      src = fetchFromGitHub {
        owner = "unhammer";
        repo = "org-rich-yank";
        rev = "d2f350c5296cf05d6c84b02762ba44f09a02b4e3";
        sha256 = "0gxb0fnh5gxjmld0hnk5hli0cvdd8gjd27m30bk2b80kwldxlq1z";
        # date = 2018-11-20T14:54:52+01:00;
      };
    };

    ovpn-mode = compileEmacsFiles {
      name = "ovpn-mode";
      src = fetchFromGitHub {
        owner = "collarchoke";
        repo = "ovpn-mode";
        rev = "dce04d9f35fd203afd098ba413595db6c2cbc051";
        sha256 = "0ix53rlwzi1mh35msh6gahfnip67p53jc3qxkbaxji7hlxi130fb";
        # date = "2019-08-11T18:00:35-04:00";
      };
    };

    ox-slack = compileEmacsFiles {
      name = "ox-slack";
      src = fetchFromGitHub {
        owner = "titaniumbones";
        repo = "ox-slack";
        rev = "96d90914e6df1a0141657fc51f1dc5bb8f1da6bd";
        sha256 = "1cda5c35wm7aqyj7yj80wkwb79dgzlzis1dlpysdxv30ahcf4w8p";
        # date = 2018-11-19T06:31:43-05:00;
      };
      buildInputs = [ self.ox-gfm ];
    };

    ox-texinfo-plus = compileEmacsFiles {
      name = "ox-texinfo-plus";
      src = fetchFromGitHub {
        owner = "tarsius";
        repo = "ox-texinfo-plus";
        rev = "e84574d315164727fb9538467ad4d24de8b3fba4";
        sha256 = "06a71bjwgzbvy5fpjg42ng3v0plpw17wx1k3y3ycj2zriybmkhfa";
        # date = 2019-06-04T14:41:35+02:00;
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
      buildInputs = [ self.dash ];
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

    spinner = compileEmacsFiles {
      name = "spinner";
      src = fetchFromGitHub {
        owner = "Malabarba";
        repo = "spinner.el";
        rev = "4b335260edcdd8dcee0811d7048bb08274e941f1";
        sha256 = "0y8nv9cxpmy98y9sk7w889f43plh0095r6vl6z8b22p3qm4rxq3m";
        # date = 2018-12-06T18:34:11-02:00;
      };
    };

    slidify-pages = compileEmacsFiles {
      name = "slidify-pages";
      src = fetchFromGitHub {
        owner = "enaeher";
        repo = "slidify-pages";
        rev = "de0c7d58779e5f8355efcbcfed3f0d4cd98a1a73";
        sha256 = "1cjmcwqyczvapsn0bsal1f3xdzzzcqmc2srhzvpb0ph2m51z1fz7";
        # date = 2015-07-07T18:43:40-05:00;
      };
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

    tla-mode = compileEmacsFiles {
      name = "tla-mode";
      src = fetchFromGitHub {
        owner = "ratish-punnoose";
        repo = "tla-mode";
        rev = "28c915aa49e043358a29bde045a68357027d96de";
        sha256 = "1vvha5ahdq2jnhwn1s4kx6wf74iz7fvfwk4sl7nb8afy0gp06f9k";
        # date = 2019-06-03T00:38:56-07:00;
      };
    };

    undo-propose = compileEmacsFiles {
      name = "undo-propose";
      src = fetchFromGitHub {
        owner = "jackkamm";
        repo = "undo-propose-el";
        rev = "505d79053590a411be6d84e1bcd4ce13485e96f0";
        sha256 = "1kvpwcry6q28cw0xrzmss0d05kzn1ay4y2c55k3sb2157izxvafn";
        # date = 2019-09-21T08:33:59-07:00;
      };
    };

    wat-mode = compileEmacsFiles {
      name = "wat-mode";
      src = fetchFromGitHub {
        owner = "devonsparks";
        repo = "wat-mode";
        rev = "f34fc84879a99130283a124cd196041b474213e1";
        sha256 = "11j7cawvy1g9llslgmyk3bnqw6qjxiil1g6jq7bza97ckfrcc1if";
        # date = 2018-10-22T18:26:10-07:00;
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

    agda2-mode =
      let Agda = pkgs.haskell.lib.dontHaddock pkgs.haskellPackages.Agda; in
      self.trivialBuild {
        pname = "agda-mode";
        version = Agda.version;

        phases = [ "buildPhase" "installPhase" ];

        # already byte-compiled by Agda builder
        buildPhase = ''
          agda=`${Agda}/bin/agda-mode locate`
          cp `dirname $agda`/*.el* .
        '';

        meta = {
          description = "Agda2-mode for Emacs extracted from Agda package";
          longDescription = ''
            Wrapper packages that liberates init.el from `agda-mode locate` magic.
            Simply add this to user profile or systemPackages and do `(require 'agda2)` in init.el.
          '';
          homepage = Agda.meta.homepage;
          license = Agda.meta.license;
        };
      };

    color-theme = lib.overrideDerivation super.color-theme (attrs: rec {
      name = "emacs-color-theme-${version}";
      version = "6.6.0";
      src = fetchurl {
        url = "http://download.savannah.nongnu.org/releases/color-theme/color-theme-${version}.tar.gz";
        sha256 = "0yx1ghcjc66s1rl0v3d4r1k88ifw591hf814ly3d73acvh15zlsn";
        # date = 2018-10-31T10:46:05-0700;
      };
    });

    doxymacs = mkDerivation rec {
      name = "emacs-doxymacs-${version}";
      version = "2017-12-10";

      src = fetchgit {
        url = git://git.code.sf.net/p/doxymacs/code.git;
        rev = "914d5cc98129d224e15bd68c39ec8836830b08a2";
        sha256 = "1xqjga5pphcfgqzj9lxfkm50sc1qag1idf54lpa23z81wrxq9dy3";
        # date = 2010-03-07T21:45:41+00:00;
      };

      buildInputs = [ self.emacs ] ++ (with pkgs; [ texinfo perl which ]);

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

    elfeed = self.melpaBuild {
      pname = "elfeed";
      version = "20180127.1742";
      src = fetchFromGitHub {
        owner = "skeeto";
        repo = "elfeed";
        rev = "69b0320156cbf7e395efa670464d4651f708332f";
        sha256 = "1nkd1ll8fjnnkqqz6x4yr7lij6kknh4mh30qf3g4kzg5gmwhbx6q";
        # date = 2019-09-06T22:12:16+02:00;
      };
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/407ae027fcec444622c2a822074b95996df9e6af/recipes/elfeed";
        sha256 = "1psga7fcjk2b8xjg10fndp9l0ib72l5ggf43gxp62i4lxixzv8f9";
        name = "elfeed";
        # date = 2019-09-25T11:38:28+0200;
      };
      packageRequires = [ self.emacs ];
      meta = {
        homepage = "https://melpa.org/#/elfeed";
        license = lib.licenses.free;
      };
    };

    emacsql-sqlite = self.melpaBuild {
      pname = "emacsql-sqlite";
      ename = "emacsql-sqlite";
      version = "20181111";
      src = fetchFromGitHub {
        owner = "skeeto";
        repo = "emacsql";
        rev = "a118b6c95af1306f0288a383d274b5dd93efbbda";
        sha256 = "1qz74rk2pskpc1k6kdpqv823i5zc39i885rww05n8lrqw456cpn0";
        # date = 2019-07-27T13:10:42-04:00;
      };
      preBuild = ''
        make LDFLAGS="-L ${self.pg}/share/emacs/site-lisp/elpa/$(echo ${self.pg.name} | sed 's/^emacs-//')"
      '';
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/13d1a86dfe682f65daf529f9f62dd494fd860be9/recipes/emacsql-sqlite";
        sha256 = "1y81nabzzb9f7b8azb9giy23ckywcbrrg4b88gw5qyjizbb3h70x";
        name = "recipe";
        # date = 2018-12-26T15:42:41-0800;
      };
      packageRequires = with self; [ emacs emacsql ];
      meta = {
        homepage = "https://melpa.org/#/emacsql-sqlite";
        license = lib.licenses.free;
      };
    };

    lua-mode = lib.overrideDerivation super.lua-mode (attrs: rec {
      name = "lua-mode-${version}";
      version = "20190113.1350";
      src = fetchFromGitHub {
        owner = "immerrr";
        repo = "lua-mode";
        rev = "95c64bb5634035630e8c59d10d4a1d1003265743";
        sha256 = "1mra4db25ds64526dsj8m5yv0kfq3lgggjh1x6xmqypdaryddbcp";
        fetchSubmodules = true;
        # date = 2019-01-13T13:50:39+03:00;
      };
    });

    multi-term = self.melpaBuild {
      pname = "multi-term";
      ename = "multi-term";
      version = "20160619.233";
      src = fetchFromGitHub {
        owner = "milkypostman";
        repo = "multi-term";
        rev = "8b163b5277f69a46184787feab9a54402622c6fc";
        sha256 = "1h39cld2p82pz80sdnzsajcs03k25ml5ld4d8hdx8hv4v96ismfz";
        # date = 2012-03-06T15:42:35-06:00;
      };
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/ae489be43b1aee93614e40f492ebdf0b98a3fbc1/recipes/multi-term";
        sha256 = "16idk4nd7qpyrvyspbrdl8gdfaclng6ny0xigk6fqdv352djalal";
        name = "recipe";
      };
      packageRequires = [];
      meta = {
        homepage = "https://melpa.org/#/multi-term";
        license = lib.licenses.free;
      };
    };

    pdf-tools = lib.overrideDerivation super.pdf-tools (attrs: {
      src = fetchFromGitHub {
        owner = "politza";
        repo = "pdf-tools";
        rev = "c851df842e05f353e4d249f2653f98418b3345d6";
        sha256 = "1ij2w7lhwx2f88m35xp56risa29qrhh2p6xnvc3rnbb9iszajs3i";
        # date = 2019-09-18T19:15:52+02:00;
      };
    });

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
      buildInputs = [ self.emacs ] ++ (with pkgs; [ texinfo perl which ]);
      meta = {
        homepage = "https://elpa.gnu.org/packages/org.html";
        license = lib.licenses.free;
      };
    };

    proof-general =
      let texinfo = pkgs.texinfo4 ;
          texLive = pkgs.texlive.combine {
            inherit (pkgs.texlive) scheme-basic cm-super ec;
          }; in mkDerivation rec {
      name = "emacs-proof-general-${version}";
      version = "2018-02-26";

      # This is the main branch
      src = fetchFromGitHub {
        owner = "ProofGeneral";
        repo = "PG";
        rev = "d53ded580e30d49e7a783280fd9ba96bc9c1c39c";
        sha256 = "17hf4mxpijvgd2jrffibcz9ps4vv8w2alcgmh78xjlb6mm0p3ls0";
        # date = 2019-08-21T10:48:33+02:00;
      };

      # src = ~/src/proof-general;

      buildInputs = [ self.emacs ] ++ (with pkgs; [ texinfo perl which ]);

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

    use-package = self.melpaBuild {
      pname = "use-package";
      version = "20180127.1411";
      src = ~/src/dot-emacs/lisp/use-package;
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/51a19a251c879a566d4ae451d94fcb35e38a478b/recipes/use-package";
        sha256 = "0d0zpgxhj6crsdi9sfy30fn3is036apm1kz8fhjg1yzdapf1jdyp";
        name = "use-package";
        # date = 2019-04-03T08:54:52-0700;
      };
      packageRequires = [ self.bind-key self.emacs ];
      meta = {
        homepage = "https://melpa.org/#/use-package";
        license = lib.licenses.free;
      };
    };

    w3m = lib.overrideDerivation super.w3m (attrs: rec {
      name = "emacs-w3m-${version}";
      version = "20190227.2349";
      src = fetchFromGitHub {
        owner = "emacs-w3m";
        repo = "emacs-w3m";
        rev = "8c647b83bc4f85f359e3d2ff6c72b8f53371a599";
        sha256 = "1vxqh01y4v9jbz17zckkcgni6myvvk4mriqg294sran83br42vc5";
        # date = 2019-09-25T07:43:44+00:00;
      };
    });
  };

  mkEmacsPackages = emacs:
    (self.emacsPackagesNgGen emacs).overrideScope (super: self:
      pkgs.lib.fix
        (pkgs.lib.extends
           myEmacsPackageOverrides
           (_: super.melpaPackages
                 // { inherit emacs;
                      inherit (super) melpaBuild trivialBuild; })));

in {

emacs = self.emacs26;
emacsPackagesNg = self.emacs26PackagesNg;

emacs26 = with pkgs; stdenv.lib.overrideDerivation
  (pkgs.emacs26.override { srcRepo = true; }) (attrs: rec {
  CFLAGS = "-O3 -Ofast " + attrs.CFLAGS;
  buildInputs = attrs.buildInputs ++
    [ libpng libjpeg libungif libtiff librsvg ] ;
});

emacs26PackagesNg = mkEmacsPackages self.emacs26;

emacs26debug = pkgs.stdenv.lib.overrideDerivation pkgs.emacs26 (attrs: rec {
  name = "${attrs.name}-debug";
  CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
  configureFlags = attrs.configureFlags ++
    [ "--enable-checking=yes,glyphs" "--enable-check-lisp-object-type" ];
});

emacs26DebugPackagesNg = mkEmacsPackages self.emacs26debug;

emacsHEAD = pkgs.stdenv.lib.overrideDerivation
  (pkgs.emacs26.override { srcRepo = true; }) (attrs: rec {
  name = "emacs-${version}${versionModifier}";
  version = "27.0";
  versionModifier = ".50";
  doCheck = false;
  CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
  src = ~/src/emacs;
  configureFlags = attrs.configureFlags ++
    [ "--enable-checking=yes,glyphs" "--enable-check-lisp-object-type" ];
});

emacsHEADPackagesNg = mkEmacsPackages self.emacsHEAD;

convertForERC = drv: pkgs.stdenv.lib.overrideDerivation drv (attrs: rec {
  name = "erc-${version}${versionModifier}";
  appName = "ERC";
  version = "27.0";
  versionModifier = ".50";
  iconFile = ./emacs/Chat.icns;

  patches = [
    ./emacs/tramp-detect-wrapped-gvfsd.patch
  ];

  preConfigure = ''
    sed -i 's|/usr/share/locale|${pkgs.gettext}/share/locale|g' \
      lisp/international/mule-cmds.el
    sed -i 's|nextstep/Emacs\.app|nextstep/${appName}.app|' configure.ac
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
  '' + attrs.preConfigure;

  postInstall =
    builtins.replaceStrings ["Emacs.app"] ["${appName}.app"] attrs.postInstall + ''
      set -x
      echo moving
      mv $out/Applications/${appName}.app/Contents/MacOS/Emacs \
         $out/Applications/${appName}.app/Contents/MacOS/${appName}
      cp "${iconFile}" $out/Applications/${appName}.app/Contents/Resources/${appName}.icns
  '';
});

emacsERC = self.convertForERC self.emacsHEAD;
emacsERCPackagesNg = mkEmacsPackages self.emacsERC;

emacsHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "emacsHEAD";
  buildInputs = [
    (self.emacsHEADPackagesNg.emacsWithPackages myPkgs)
  ];
};

emacsERCEnv = myPkgs: pkgs.myEnvFun {
  name = "emacsERC";
  buildInputs = [
    (self.emacsERCPackagesNg.emacsWithPackages myPkgs)
  ];
};

emacs26Env = myPkgs: pkgs.myEnvFun {
  name = "emacs26";
  buildInputs = [
    (self.emacs26PackagesNg.emacsWithPackages myPkgs)
  ];
};

emacs26DebugEnv = myPkgs: pkgs.myEnvFun {
  name = "emacs26debug";
  buildInputs = [
    (self.emacs26DebugPackagesNg.emacsWithPackages myPkgs)
  ];
};

}
