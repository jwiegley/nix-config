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


    magit-annex        = addBuildInputs super.magit-annex        [ pkgs.git ];
    magit-filenotify   = addBuildInputs super.magit-filenotify   [ pkgs.git ];
    magit-gitflow      = addBuildInputs super.magit-gitflow      [ pkgs.git ];
    magit-imerge       = addBuildInputs super.magit-imerge       [ pkgs.git ];
    magit-lfs          = addBuildInputs super.magit-lfs          [ pkgs.git ];
    magit-tbdiff       = addBuildInputs super.magit-tbdiff       [ pkgs.git ];
    orgit              = addBuildInputs super.orgit              [ pkgs.git ];


    company-coq   = withPatches super.company-coq   [ ./emacs/patches/company-coq.patch ];
    esh-buf-stack = withPatches super.esh-buf-stack [ ./emacs/patches/esh-buf-stack.patch ];
    git-link      = withPatches super.git-link      [ ./emacs/patches/git-link.patch ];
    haskell-mode  = withPatches super.haskell-mode  [
      ./emacs/patches/haskell-mode.patch
    ];
    helm-google   = withPatches super.helm-google   [ ./emacs/patches/helm-google.patch ];
    magit         = withPatches super.magit         [ ./emacs/patches/magit.patch ];
    noflet        = withPatches super.noflet        [ ./emacs/patches/noflet.patch ];
    org-ref       = withPatches super.org-ref       [ ./emacs/patches/org-ref.patch ];
    pass          = withPatches super.pass          [ ./emacs/patches/pass.patch ];


    ascii = compileEmacsWikiFile {
      name = "ascii.el";
      sha256 = "05fjsj5nmc05cmsi0qj914dqdwk8rll1d4dwhn0crw36p2ivql75";
      # date = 2019-04-03T08:43:15-0700;
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
      sha256 = "0gmlly1pq5zp7qdcmck90nm0n8j9lahhr26pljb9wjqy4cgzr5ls";
      # date = 2019-04-03T08:43:35-0700;
    };

    highlight-cl = compileEmacsWikiFile {
      name = "highlight-cl.el";
      sha256 = "0r3kzs2fsi3kl5gqmsv75dc7lgfl4imrrqhg09ij6kq1ri8gjxjw";
      # date = 2019-04-03T08:43:36-0700;
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
      sha256 = "12pzik5plywil0rz95rqb5qdqwdawkbwhmqab346yizhlp6i4fq6";
      # date = 2019-04-03T08:51:32-0700;
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
        sha256 = "01q9gnkgjl5dfsvw639kq8xi7vlgfyn5iz01ipn85q37wvibvlij";
        # date = 2019-04-03T08:51:54-0700;
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
        sha256 = "0vinzlin17ghp2xg0mzxw58jp08fg0jxmq228rd6n017j48b89ck";
        # date = 2019-04-03T08:51:59-0700;
      };
    };


    anki-editor = compileEmacsFiles {
      name = "anki-editor";
      src = fetchFromGitHub {
        owner = "louietan";
        repo = "anki-editor";
        rev = "115ce2e2e62deb8dbca91fd84c7999ba80916c89";
        sha256 = "0njwsq03h36hqw55xk6n8225k52nlw1lq0mc9pzww2bf7dccjl9r";
        # date = 2018-12-30T23:53:14-08:00;
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
        rev = "03ec5a4ab6fb0d7ad4c7a4793c1478110da3646c";
        sha256 = "0jv18g9yfzhicfcdn98azb2q5v9f64087537csl4vibgf3hs0yfy";
        # date = 2019-02-19T08:01:57+01:00;
      };
    };

    deadgrep = compileEmacsFiles {
      name = "deadgrep";
      src = fetchFromGitHub {
        owner = "Wilfred";
        repo = "deadgrep";
        rev = "160e7adb7f043fc42ba6d4d891ad50ef1e063be7";
        sha256 = "1sm92hj4ilq0h82fy5k5nzn7jq56yw2665ikqdcj89k9xldin6xi";
        # date = 2019-03-14T22:07:10+00:00;
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
        rev = "d1df599254f4c250720ae98dd69dada89535a295";
        sha256 = "10h59zd9hq81dyjw558k417kaqs5m9bhmx8mndcshh4cn1xfp5j3";
        # date = 2019-04-02T17:25:09+02:00;
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
        rev = "9c3ffe30fba5d02e9951e76d1a5be2ed046663da";
        sha256 = "078rv6f2p3wrznhgvmkhd071bwy72007f5l2m2a0r1k2i3vbfaja";
        # date = 2019-03-27T00:32:52-07:00;
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
        rev = "5bf3b915bdb78f58fc657e616262d967266a4500";
        sha256 = "1nfabcphfsbza4zrw4f23ajv6bh4jrma0k9ygphv7pzg7hc48jf8";
        # date = 2019-03-18T17:08:00+01:00;
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
        rev = "14e5347c98f42166ad7061b8663d368bb0d4fba4";
        sha256 = "1czaf38w0z1pkjwmlhxrln9nmd3zp1j7gmhaf82bw15d8xcl4kbh";
        # date = 2019-01-14T08:50:27-06:00;
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
        rev = "1e53bed4d47c526c71113569f592c82845a17784";
        sha256 = "172s5lxlns633gbi6sq6iws269chalh5k501n3wffp5i3b2xzdyq";
        # date = 2019-01-19T10:25:21+01:00;
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
        rev = "a7c225948605198c5d277090d7c22af310ce2e24";
        sha256 = "1afsh27y5yl7yg7m4i2j0mwc2rlgfn29ml3lbg2mn86p5wqanjqy";
        # date = "2018-05-03T12:39:41-04:00";
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
        rev = "2f4b8a6055f37dbb19219c3a57c6d99ed8bc1580";
        sha256 = "0awb08v9pcb92hk398fg2nnbv258v12nrsbi0jnndsrgsyp6i4pk";
        # date = 2019-02-23T23:08:56+01:00;
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
        rev = "ab604ba3739ad613599ccee7bc7cb4c9a7b84f5c";
        sha256 = "1q9pnf4hdan7y4gyxssgdarprdf3wjv5gflnirbpfqq7fyfihwxw";
        # date = 2016-04-06T23:50:23-07:00;
      };
    };

    undo-propose = compileEmacsFiles {
      name = "undo-propose";
      src = fetchFromGitHub {
        owner = "jackkamm";
        repo = "undo-propose-el";
        rev = "036e66c1ac4b0358b34727d2c9b65853347dad89";
        sha256 = "1ah2x0fwf2ybz3i4cjs19fmx7aq1xfgnh4x623qy12v7ab4pvd3m";
        # date = 2019-03-22T09:17:36-07:00;
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
      let Agda = pkgs.haskell.lib.dontHaddock pkgs.haskell.packages.ghc844.Agda; in
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
        rev = "e3379ad22fb286ddcdfe5a27177d9bfa9e83e883";
        sha256 = "12b0nrrj8mpjc9hj6jyv1sjd6xidxxllx9d1cmp7idx1arbvm7m3";
        # date = 2019-03-26T09:04:11-04:00;
      };
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/407ae027fcec444622c2a822074b95996df9e6af/recipes/elfeed";
        sha256 = "1psga7fcjk2b8xjg10fndp9l0ib72l5ggf43gxp62i4lxixzv8f9";
        name = "elfeed";
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
        rev = "5ebd12b6ffaa9fbadefe8518eab07a028bbaf7c1";
        sha256 = "19anva1mcm89hylhdjjjsc3gc32kv2wqp5qs6h7rca059kkqj277";
        # date = 2019-03-10T14:22:13+01:00;
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
        sha256 = "0cawb544qylifkvqads307n0nfqg7lvyphqbpbzr2xvr5iyi4901";
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
        rev = "9a63f3909e5a331b6974deb03abd2c4bad42c2d9";
        sha256 = "11i4kbwclwyvznyd9q69fq36fjasvs72ziz0555hl3fjbbq0n71q";
        # date = 2019-03-09T08:44:42+01:00;
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
        rev = "8f90ac961c22099a615c03ed07576aaef820e06d";
        sha256 = "07rwy1q0pii1k7z18hpfs768w07n7qg0wrvcqkrjfii3hx19vbwf";
        # date = 2019-02-12T15:33:53+01:00;
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
        rev = "84ef5a917182d3fc5417c763fd9b3fe6db32d1fb";
        sha256 = "1qc8la7y121pj7l1g98wcafr3cjs5dbafcv1k9d9xiadpi21bir2";
        # date = 2019-03-14T01:54:38+00:00;
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
  name = "emacs-${version}${versionModifier}";
  version = "26.2";
  versionModifier = "";

  doCheck = false;

  buildInputs = (attrs.buildInputs or []) ++
    [ git libpng.dev libjpeg.dev libungif libtiff.dev librsvg.dev
      imagemagick.dev ];

  patches = lib.optionals stdenv.isDarwin
    [ ./emacs/tramp-detect-wrapped-gvfsd.patch
      ./emacs/patches/at-fdcwd.patch
      ./emacs/patches/emacs-26.patch ];

  CFLAGS = "-Ofast -momit-leaf-frame-pointer -DMAC_OS_X_VERSION_MAX_ALLOWED=101200";

  src = fetchgit {
    url = https://git.savannah.gnu.org/git/emacs.git;
    rev = "emacs-${version}${versionModifier}";
    sha256 = "0wln9zadc2n5vxi5z20mx2i1544ni8l4z81kh9dda10jz8ddwsqj";
    # date = 2019-02-20T07:33:53-08:00;
  };
});

emacs26PackagesNg = mkEmacsPackages self.emacs26;

emacs26debug = pkgs.stdenv.lib.overrideDerivation self.emacs26 (attrs: rec {
  name = "emacs-26.2-debug";
  doCheck = true;
  CFLAGS = "-O0 -g3 -DMAC_OS_X_VERSION_MAX_ALLOWED=101200";
  configureFlags = [ "--with-modules" ] ++
   [ "--with-ns" "--disable-ns-self-contained"
     "--enable-checking=yes,glyphs"
     "--enable-check-lisp-object-type" ];
});

emacs26DebugPackagesNg = mkEmacsPackages self.emacs26debug;

emacsHEAD = with pkgs; stdenv.lib.overrideDerivation self.emacs26 (attrs: rec {
  name = "emacs-${version}${versionModifier}";
  version = "27.0";
  versionModifier = ".50";

  doCheck = false;

  patches = lib.optionals stdenv.isDarwin
    [ ./emacs/tramp-detect-wrapped-gvfsd.patch
      ./emacs/patches/at-fdcwd.patch
    ];

  src = ~/src/emacs;
});

emacsHEADPackagesNg = mkEmacsPackages self.emacsHEAD;

convertForERC = drv: pkgs.stdenv.lib.overrideDerivation drv (attrs: rec {
  name = "erc-${version}${versionModifier}";
  appName = "ERC";
  version = "27.0";
  versionModifier = ".50";
  iconFile = ./emacs/Chat.icns;

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
      mv $out/Applications/${appName}.app/Contents/MacOS/Emacs \
         $out/Applications/${appName}.app/Contents/MacOS/${appName}
      cp "${iconFile}" $out/Applications/${appName}.app/Contents/Resources/${appName}.icns
    '';
});

rewrapForERC = drv: pkgs.stdenv.lib.overrideDerivation drv (attrs: rec {
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
    (self.rewrapForERC (self.emacsERCPackagesNg.emacsWithPackages myPkgs))
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
