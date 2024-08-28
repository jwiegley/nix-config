self: pkgs:

let
  myEmacsPackageOverrides = eself: esuper:
    let
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub stdenv lib;
      inherit (stdenv) mkDerivation;

      withPatches = pkg: patches:
        pkg.overrideAttrs(attrs: { inherit patches; });

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

    in rec {

    edit-env        = compileLocalFile "edit-env.el";
    edit-var        = compileLocalFile "edit-var.el";
    # flymake         = compileLocalFile "flymake-1.0.9.el";
    # project         = compileLocalFile "project-0.5.3.el";
    rs-gnus-summary = compileLocalFile "rs-gnus-summary.el";
    supercite       = compileLocalFile "supercite.el";

    magit-annex      = addBuildInputs esuper.magit-annex        [ pkgs.git ];
    magit-filenotify = addBuildInputs esuper.magit-filenotify   [ pkgs.git ];
    magit-gitflow    = addBuildInputs esuper.magit-gitflow      [ pkgs.git ];
    magit-imerge     = addBuildInputs esuper.magit-imerge       [ pkgs.git ];
    magit-lfs        = addBuildInputs esuper.magit-lfs          [ pkgs.git ];
    magit-tbdiff     = addBuildInputs esuper.magit-tbdiff       [ pkgs.git ];
    orgit            = addBuildInputs esuper.orgit              [ pkgs.git ];

    company-coq   = withPatches esuper.company-coq   [ ./emacs/patches/company-coq.patch ];
    esh-buf-stack = withPatches esuper.esh-buf-stack [ ./emacs/patches/esh-buf-stack.patch ];
    helm-google   = withPatches esuper.helm-google   [ ./emacs/patches/helm-google.patch ];
    magit         = withPatches esuper.magit         [ ./emacs/patches/magit.patch ];
    noflet        = withPatches esuper.noflet        [ ./emacs/patches/noflet.patch ];
    pass          = withPatches esuper.pass          [ ./emacs/patches/pass.patch ];

    ########################################################################

    ascii = compileEmacsWikiFile {
      name = "ascii.el";
      sha256 = "1ijpnk334fbah94vm7dkcd2w4zcb0l7yn4nr9rwgpr2l25llnr0f";
      # date = 2021-03-26T13:22:06-0700;
    };

    backup-each-save = compileEmacsWikiFile {
      name = "backup-each-save.el";
      sha256 = "0b9vvi2m0fdv36wj8mvawl951gjmg3pypg08a8n6rzn3rwg0fwz7";
      # date = 2023-04-20T11:04:05-0700;
    };

    col-highlight = compileEmacsWikiFile {
      name = "col-highlight.el";
      sha256 = "0na8aimv5j66pzqi4hk2jw5kk00ki99zkxiykwcmjiy3h1r9311k";
      # date = 2022-06-05T10:05:24-0700;

      buildInputs = with eself; [ vline ];
    };

    crosshairs = compileEmacsWikiFile {
      name = "crosshairs.el";
      sha256 = "0ld30hwcxvyqfaqi80nvrlflpzrclnjcllcp457hn4ydbcf2is9r";
      # date = 2022-06-05T10:05:18-0700;

      buildInputs = with eself; [ hl-line-plus col-highlight vline ];
    };

    cursor-chg = compileEmacsWikiFile {
      name = "cursor-chg.el";
      sha256 = "1zmwh0z4g6khb04lbgga263pqa51mfvs0wfj3y85j7b08f2lqnqn";
      # date = 2022-06-05T10:05:26-0700;
    };

    dired-plus = compileEmacsWikiFile {
      name = "dired+.el";
      sha256 = "sha256-YAQRhSaPGvwFDJ7c635KX/RxC3l/h/clJhNK69msY8g=";
      # date = 2023-06-09T13:28:36-0700;
    };

    erc-highlight-nicknames = compileEmacsWikiFile {
      name = "erc-highlight-nicknames.el";
      sha256 = "01r184q86aha4gs55r2vy3rygq1qnxh1bj9qmlz97b2yh8y17m50";
      # date = 2021-03-26T13:22:24-0700;
    };

    hexrgb = compileEmacsWikiFile {
      name = "hexrgb.el";
      sha256 = "18hb8brf7x92aidjfgczxangri6rkqq4x5d06lh41193f97rslm8";
      # date = 2021-03-26T13:22:26-0700;
    };

    highlight-cl = compileEmacsWikiFile {
      name = "highlight-cl.el";
      sha256 = "0r3kzs2fsi3kl5gqmsv75dc7lgfl4imrrqhg09ij6kq1ri8gjxjw";
      # date = 2021-03-26T13:22:27-0700;
    };

    hl-line-plus = compileEmacsWikiFile {
      name = "hl-line+.el";
      sha256 = "1ns064l1c5g3dnhx5d2sn43w9impn58msrywsgq0bdyzikg7wwh2";
      # date = 2022-06-05T10:05:32-0700;
    };

    message-x = compileEmacsWikiFile {
      name = "message-x.el";
      sha256 = "05ic97plsysh4nqwdrsl5m9f24m11w24bahj8bxzfdawfima2bkf";
      # date = 2021-03-26T13:22:29-0700;
    };

    palette = compileEmacsWikiFile {
      name = "palette.el";
      sha256 = "149y6bmn0njgq632m9zdnaaw7wrvxvfqndpqlgcizn6dwzixiih6";
      # date = 2021-03-26T13:22:30-0700;

      buildInputs = with eself; [ hexrgb ];
    };

    popup-pos-tip = compileEmacsWikiFile {
      name = "popup-pos-tip.el";
      sha256 = "0dhyzfsl01y61m53iz38a1vcvclr98wamsh0nishw0by1dnlb17x";
      # date = 2021-03-26T13:22:32-0700;

      buildInputs = with eself; [ popup pos-tip ];
    };

    popup-ruler = compileEmacsWikiFile {
      name = "popup-ruler.el";
      sha256 = "0fszl969savcibmksfkanaq11d047xbnrfxd84shf9z9z2i3dr43";
      # date = 2021-03-26T13:22:36-0700;
    };

    pp-c-l = compileEmacsWikiFile {
      name = "pp-c-l.el";
      sha256 = "03mhd8lja71163jg6fj4d4hy2dwb1c5j46sn9yq6m9wz413a4pmd";
      # date = 2021-03-26T13:22:37-0700;
    };

    tidy = compileEmacsWikiFile {
      name = "tidy.el";
      sha256 = "0psci55a3angwv45z9i8wz8jw634rxg1xawkrb57m878zcxxddwa";
      # date = 2021-03-26T13:22:39-0700;
    };

    vline = compileEmacsWikiFile {
      name = "vline.el";
      sha256 = "1ys6928fgk8mswa4gv10cxggir8acck27g78cw1z3pdz5gakbgnj";
      # date = 2022-06-05T10:05:37-0700;
    };

    xray = compileEmacsWikiFile {
      name = "xray.el";
      sha256 = "1s25z9iiwpm1sp3yj9mniw4dq7dn0krk4678bgqh464k5yvn6lyk";
      # date = 2021-03-26T13:22:41-0700;
    };

    yaoddmuse = compileEmacsWikiFile {
      name = "yaoddmuse.el";
      sha256 = "0h3s3mdfz0czgz1cj415k170g7mbbqmsinw0xr7qmk050i154iis";
      # date = 2021-03-26T13:22:43-0700;
    };

    ########################################################################

    bytecomp-simplify = compileEmacsFiles {
      name = "bytecomp-simplify.el";
      src = fetchurl {
        url = https://download.tuxfamily.org/user42/bytecomp-simplify.el;
        sha256 = "1yq0wqgva8yidyd46cqag0ds0cyzl7q8rpd2cmksp68k4zlsxwyv";
        # date = 2022-01-03T11:56:57-0800;
      };
    };

    jobhours = compileEmacsFiles {
      name = "jobhours";
      src = ~/src/hours;
    };

    ########################################################################

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
        rev = "e07702390622534dce2a3a250e9e295041aa7e65";
        sha256 = "0vjz06rmjy6ag2pki6x8w6il53yq0p6d17dy7k2ny8n4caw08fhj";
        # date = 2024-02-11T01:19:19+01:00;
      };
    };

    cape-yasnippet = compileEmacsFiles {
      name = "cape-yasnippet";
      src = fetchFromGitHub {
        owner = "elken";
        repo = "cape-yasnippet";
        rev = "744dedb7837d0c7e07817d36ec752a0cd813f55c";
        sha256 = "09smh2r0yysxqg3ixx0nssdz8kzqy5s1d687vbdijvhg3prcc8q4";
        # date = 2024-04-21T19:48:14+01:00;
      };
      buildInputs = with eself; [ cape yasnippet ];
    };

    casual-lib = compileEmacsFiles {
      name = "casual-lib";
      src = (fetchFromGitHub {
        owner = "kickingvegas";
        repo = "casual-lib";
        rev = "74ae8cf0b88efefe9afc58605ccb1576ec1b035a";
        sha256 = "02pxnhp5idn6ypk5s5nl0df1s2pgmyy7g5p3hiyb52m972y1if35";
        # date = "2024-07-16T13:21:37-07:00";
      }) + "/lisp";
    };

    casual-dired = compileEmacsFiles {
      name = "casual-dired";
      src = (fetchFromGitHub {
        owner = "kickingvegas";
        repo = "casual-dired";
        rev = "4be72b52f91700cdb529a185b8f6f21bd0a86542";
        sha256 = "1lilb3gi8mmiiwdwr3xsy9pvm3nh5crzsvbh45dsk72wwgzjp94i";
        # date = "2024-07-16T14:20:23-07:00";
      }) + "/lisp";
      buildInputs = with eself; [ casual-lib ];
    };

    casual-calc = compileEmacsFiles {
      name = "casual-calc";
      src = (fetchFromGitHub {
        owner = "kickingvegas";
        repo = "casual-calc";
        rev = "47d8c4fd2b4a2d91d3891320a42451577d9c804a";
        sha256 = "0qdi6p3aybg0zwscf35l2dx51q7h4rz2g7r4xf7ml520dag7h5cw";
        # date = "2024-06-28T16:32:16-07:00";
      }) + "/lisp";
      buildInputs = with eself; [ casual-lib ];
    };

    casual-ibuffer = compileEmacsFiles {
      name = "casual-ibuffer";
      src = (fetchFromGitHub {
        owner = "kickingvegas";
        repo = "casual-ibuffer";
        rev = "877bffe4e69f2715f5f84ad15ca54f4a14493b80";
        sha256 = "0gpklvr70vwkhsbb0s9khaj4mv8mizdyjrag8q6f5ajivaxp67vi";
        # date = "2024-07-29T20:29:38-07:00";
      }) + "/lisp";
      buildInputs = with eself; [ casual-lib ];
    };

    casual-bookmarks = compileEmacsFiles {
      name = "casual-bookmarks";
      src = (fetchFromGitHub {
        owner = "kickingvegas";
        repo = "casual-bookmarks";
        rev = "e5f91bcc646d62166afaca9e9e4d6b904b4d0244";
        sha256 = "1h1575wj1yq01gjbjs834y734a2qyqls0fqc7y3dqbzkrbw6q0sw";
        # date = "2024-07-29T20:49:47-07:00";
      }) + "/lisp";
      buildInputs = with eself; [ casual-lib ];
    };

    consult-gh = compileEmacsFiles {
      name = "consult-gh";
      src = fetchFromGitHub {
        owner = "armindarvish";
        repo = "consult-gh";
        rev = "3a07139a1f7e38b959ce177a122c8f47c401d7fa";
        sha256 = "1nimy1mfnm3p8ikn0hcv4sq1nrw4ryivx7q08yv30hvfjhdni685";
        # date = 2024-04-23T20:41:51-07:00;
      };
      buildInputs = with eself; [ consult embark ];
    };

    consult-hoogle = compileEmacsFiles {
      name = "consult-hoogle";
      src = fetchgit {
        url = "https://codeberg.org/rahguzar/consult-hoogle.git";
        rev = "188c8d90a04adeb08c61a0835f5f9a9a10255495";
        sha256 = "007552brmggivrpc8s3zlqq74mksx3rvfh0ald2j655nplf2v4w9";
        # date = 2024-04-27T15:18:42+02:00;
      };
      buildInputs = with eself; [ consult haskell-mode ];
    };

    dired-hist = compileEmacsFiles {
      name = "dired-hist";
      src = fetchFromGitHub {
        owner = "karthink";
        repo = "dired-hist";
        rev = "94b09260ac964e3d856c018d66af3214915dd826";
        sha256 = "0h5idb2q52yly8dcsrfr2prn20n3q2rhzk3ss5a0xj36i9wls275";
        # date = 2022-02-28T13:43:50-08:00;
      };
    };

    egerrit = compileEmacsFiles {
      name = "egerrit";
      src = fetchgit {
        url = "https://git.sr.ht/~niklaseklund/egerrit";
        rev = "8953a3b9ea9f77bb75ebb6ba55833cb08c34536a";
        sha256 = "0mhk53y1yzy8ymir8l7vzg4d86rnhm0f5jdlbmliw4avyhvc396c";
        # date = 2022-09-27T12:47:09+02:00;
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

    gptel = compileEmacsFiles {
      name = "gptel";
      src = fetchFromGitHub {
        owner = "karthink";
        repo = "gptel";
        rev = "9a5a4a60d5aa0bad11f632135bacaf4bf592d56a";
        sha256 = "16f8bb9qlin0x4iv6g14bha5dywgxfcqmnpqzypfhr8wjqdkpb6n";
        # date = 2024-03-21T11:30:30-07:00;
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

    # lean4-mode = compileEmacsFiles {
    #   name = "lean4-mode";
    #   src = fetchFromGitHub {
    #     owner = "myuhe";
    #     repo = "moccur-edit.el";
    #     rev = "026f5dd4159bd1b68c430ab385757157ba01a361";
    #     sha256 = "1qikrqs69zqzjpz8bchjrg96bzhj7cbcwkvgsrrx113p420k90zx";
    #     # date = 2015-03-01T18:04:32+09:00;
    #   };
    #   buildInputs = with eself; [ color-moccur ];
    # };

    moccur-edit = compileEmacsFiles {
      name = "moccur-edit";
      src = fetchFromGitHub {
        owner = "myuhe";
        repo = "moccur-edit.el";
        rev = "026f5dd4159bd1b68c430ab385757157ba01a361";
        sha256 = "1qikrqs69zqzjpz8bchjrg96bzhj7cbcwkvgsrrx113p420k90zx";
        # date = 2015-03-01T18:04:32+09:00;
      };
      buildInputs = with eself; [ color-moccur ];
    };

    org-annotate = compileEmacsFiles {
      name = "org-annotate";
      src = fetchFromGitHub {
        owner = "girzel";
        repo = "org-annotate";
        rev = "0297290f1cb1d31b264632e3f4cb4013956b5b94";
        sha256 = "1qbhz441d7cvsqbsr6k4f34kgpvinc9cji3rxxw4hv43ar58c5xf";
        # date = 2022-02-08T09:29:08-08:00;
      };
    };

    ob-emamux = compileEmacsFiles {
      name = "ob-emamux";
      src = fetchFromGitHub {
        owner = "jackkamm";
        repo = "ob-emamux";
        rev = "397760d24905ef1f00090586ea38556e6f680780";
        sha256 = "1a4r2f3682yrnq8f595cbq8ngf2arikdn2i0w1pf1mrm6ai5z3q9";
        # date = 2019-05-22T22:30:29-07:00;
      };
      buildInputs = with eself; [ emamux ];
    };

    org-extra-emphasis = compileEmacsFiles {
      name = "org-extra-emphasis";
      src = fetchFromGitHub {
        owner = "QiangF";
        repo = "org-extra-emphasis";
        rev = "d5849bb4f5327273b5a51fa6ce0cf623c58bbb16";
        sha256 = "0rgvnfzm3v546zxkxs601qdqz9pd38w55gbv00ca453mp2np6r8g";
        # date = 2023-12-01T08:29:06+05:30;
      };
    };

    org-pretty-table = compileEmacsFiles {
      name = "org-pretty-table";
      src = fetchFromGitHub {
        owner = "Fuco1";
        repo = "org-pretty-table";
        rev = "38e4354bbf7a8d08294babd067fac697038119b1";
        sha256 = "1bl2qsh871m9wp39lq7xzhd2z77vjjla8gijpfq899313yhfgq91";
        # date = 2023-03-19T15:52:27+01:00;
      };
      buildInputs = with eself; [
        org
      ];
    };

    org-roam-nursery = compileEmacsFiles {
      name = "org-roam-nursery";
      src = fetchFromGitHub {
        owner = "chrisbarrett";
        repo = "nursery";
        rev = "00a169c75b934a2eb42ea8620e8eebf34577d4ca";
        sha256 = "0715bcqhgj503380fr8wgq41kg22x05qwykm5230zka74x6x7vy7";
        # date = 2024-05-03T20:50:59+12:00;
      };
      preBuild = "cd lisp";
      buildInputs = with eself; [
        org-roam persist ht async f magit org-drill ts pcre2el consult memoize
      ];
    };

    ox-texinfo-plus = compileEmacsFiles {
      name = "ox-texinfo-plus";
      src = fetchFromGitHub {
        owner = "tarsius";
        repo = "ox-texinfo-plus";
        rev = "1dfe1c01d34a979ce870269d2c964007f50449d5";
        sha256 = "0hz2z063nrzwkr023x5mfpgvl5rk2nf0vs9c2rsy5hfpz1s9ncw0";
        # date = 2022-03-05T23:47:11+01:00;
      };
    };

    per-window-point = compileEmacsFiles {
      name = "per-window-point";
      src = fetchFromGitHub {
        owner = "alpaker";
        repo = "Per-Window-Point";
        rev = "deb161520428e60fdc353335b46eb1f5392d96f8";
        sha256 = "1fj65r5vlkihgx6n2j7kdnragz3apy3428lbs6y23lfcs6q8l18z";
        # date = 2020-10-22T10:30:08-07:00;
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
      buildInputs = with eself; [ dash ];
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
        rev = "525122ffb94ae4ac160de72c2ee0ade331d2e80a";
        sha256 = "155h9cqwr74bf1kcjk5bwbcsdg86pbi0v2j60vmd6yd0f5j4kfwq";
        # date = 2021-03-06T13:28:31+09:00;
      };
      patches = [ ./emacs/patches/sky-color-clock.patch ];
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

    vcard-mode = compileEmacsFiles {
      name = "vcard-mode";
      src = fetchFromGitHub {
        owner = "dochang";
        repo = "vcard-mode";
        rev = "ab1a2885a5720d7fb02d9b6583ee908ba2260b78";
        sha256 = "0w44ax9dxkj8mh4np9mg3yp2yakjwrgy13izq53p0vimrhywza0w";
        # date = 2019-01-29T00:54:40+08:00;
      };
    };

    vterm-tmux = compileEmacsFiles {
      name = "vterm-tmux";
      src = fetchgit {
        url = https://codeberg.org/olivermead/vterm-tmux.git;
        rev = "a847c88918beff0ce4697ec4d4f0fcb9ec57bafe";
        sha256 = "1igljgjhn55x9gj7fdikdiaxcb73v62j9s70wq4ypk4b4hxac3l4";
        # date = 2022-11-23T16:18:04+00:00;
      };
      buildInputs = with eself; [ vterm multi-vterm ];
    };

    wat-mode = compileEmacsFiles {
      name = "wat-mode";
      src = fetchFromGitHub {
        owner = "devonsparks";
        repo = "wat-mode";
        rev = "46b4df83e92c585295d659d049560dbf190fe501";
        sha256 = "1nn6h71qdi1ka4d84fa6g0i74zss2mfcixrc7pf3vy2q6kfmapld";
        # date = 2022-07-12T19:51:49-07:00;
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

    ########################################################################

    agda2-mode = compileEmacsFiles {
      name = "agda2-mode";
      src = (fetchFromGitHub {
        owner = "agda";
        repo = "agda";
        rev = "20ad6b5d02f7a647e83cc493d8b4e11e22cac8c9";
        sha256 = "142x7466kwvc19m1c2pz66i7ni5b5jvkpgdpc34di8ml6rvrfcqf";
        # date = 2024-06-27T17:34:53+02:00;
      }) + "/src/data/emacs-mode";
    };

    auctex = eself.elpaBuild {
      pname = "auctex";
      ename = "auctex";
      version = "14.0.6";
      src = fetchurl {
        url = "https://elpa.gnu.org/packages/auctex-14.0.6.tar";
        sha256 = "0cajri7x6770wjkrasa0p2s0dvcp74fpv1znac5wdfiwhvl1i9yr";
        # date = 2024-08-01T11:08:09-0700;
      };
      packageRequires = with eself; [ cl-lib emacs ];
      meta = {
        homepage = "https://elpa.gnu.org/packages/auctex.html";
        license = lib.licenses.free;
      };
    };

    pdf-tools = esuper.pdf-tools.overrideAttrs (old: {
      nativeBuildInputs = [
        self.autoconf
        self.automake
        self.pkg-config
        self.removeReferencesTo
      ];
      buildInputs = old.buildInputs ++ [ self.libpng self.zlib self.poppler ];
      preBuild = ''
        make server/epdfinfo
        remove-references-to \
          -t ${self.stdenv.cc.libc} \
          -t ${self.glib.dev} \
          -t ${self.libpng.dev} \
          -t ${self.poppler.dev} \
          -t ${self.zlib.dev} \
          -t ${self.cairo.dev} \
          server/epdfinfo
      '';
      recipe = self.writeText "recipe" ''
        (pdf-tools
        :repo "politza/pdf-tools" :fetcher github
        :files ("lisp/pdf-*.el" "server/epdfinfo"))
      '';
    });

    proof-general =
      let texinfo = pkgs.texinfo4 ;
          texLive = pkgs.texlive.combine {
            inherit (pkgs.texlive) scheme-basic cm-super ec;
          }; in mkDerivation rec {
      name = "emacs-proof-general-${version}";
      version = "4.5";

      # This is the main branch
     src = fetchFromGitHub {
        owner = "ProofGeneral";
        repo = "PG";
        rev = "911cf014b899212815c2ec8d3e8c8b88be0df57b";
        sha256 = "12a1sgk6141znagq0p7xnflcxhm7s8gccg24mkrccbiykyxif8jz";
        # date = "2023-04-07T11:09:09+02:00";
      };

      # src = ~/src/proof-general;

      buildInputs = [ eself.emacs ] ++ (with pkgs; [ texinfo perl which ]);

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

    xeft = mkDerivation rec {
      name = "xeft-${version}";
      version = "3.0";

      src = fetchgit {
        url = https://git.sr.ht/~casouri/xeft;
        rev = "e88f73979d50247d9fc1ba730022caaffb5bc317";
        sha256 = "1n01j3iw1nplsdcqn91rmcm3ka0rxvsnbd0kwfjmj8zvbgvsvzfn";
        # date = 2023-03-22T15:39:50-07:00;
      };

      propagatedBuildInputs = [ eself.emacs ] ++ (with pkgs; [
        xapian
      ]);

      makeFlags = [
        "PREFIX=$(out)"
        "CXX=${stdenv.cc.targetPrefix}c++"
        "LDFLAGS=-L${pkgs.xapian}/lib"
      ];

      buildPhase = ''
        make xapian-lite.${if stdenv.hostPlatform.isDarwin then "dylib" else "so"}
        export HOME=$out
        ${eself.emacs}/bin/emacs -Q -nw -L . --batch -f batch-byte-compile *.el
      '';
      installPhase = ''
        mkdir -p $out/share/emacs/site-lisp
        # mkdir -p $out/lib
        cp xapian-lite.${if stdenv.hostPlatform.isDarwin then "dylib" else "so"} \
           $out/share/emacs/site-lisp/
           # $out/lib
        mkdir -p $out/share/emacs/site-lisp
        cp -p *.el* $out/share/emacs/site-lisp/
      '';
    };
  };

  mkEmacsPackages = emacs:
    pkgs.lib.recurseIntoAttrs
    ((self.emacsPackagesFor emacs).overrideScope' (_: super:
       pkgs.lib.fix
         (pkgs.lib.extends
            myEmacsPackageOverrides
            (_: super.elpaPackages
             // super.melpaPackages
             // { inherit emacs;
                  inherit (super) elpaBuild melpaBuild trivialBuild; }))));

in {

emacs             = if pkgs.stdenv.targetPlatform.isx86_64
                    then self.emacs29MacPort
                    else self.emacs29;
emacsPackages     = self.emacs29MacPortPackages;
emacsPackagesNg   = self.emacs29MacPortPackagesNg;

emacs29           = pkgs.emacs29;
emacs29Packages   = self.emacs29PackagesNg;
emacs29PackagesNg = mkEmacsPackages self.emacs29;


# jww (2023-06-09): These changes allow emacs29-macport to build on aarch64-darwin
emacs29MacPortAlt = pkgs.emacs29-macport.overrideAttrs (o: {
  buildInputs = o.buildInputs ++
    (with pkgs.darwin.apple_sdk_11_0.frameworks; [
      UniformTypeIdentifiers Accelerate
    ]);
  patches = o.patches ++ [
    ./emacs/0002-mac-gui-loop-block-autorelease.patch
  ];
});

emacs29MacPort =
  (if pkgs.stdenv.targetPlatform.isx86_64
   then pkgs.emacs29-macport
   else self.emacs29MacPortAlt).overrideAttrs (o: {
     configureFlags = o.configureFlags ++ [ "--with-natural-title-bar" ];
   });

emacs29MacPortPackages   = self.emacs29MacPortPackagesNg;
emacs29MacPortPackagesNg = mkEmacsPackages self.emacs29MacPort;

# emacsHEAD = with pkgs; (self.emacs29.override { srcRepo = true; }).overrideAttrs(attrs: rec {
#   name = "emacs-${version}${versionModifier}";
#   version = "29.0";
#   versionModifier = ".90";
#   src = pkgs.nix-gitignore.gitignoreSource [] ~/src/emacs;
#   patches = [
#     ./emacs/clean-env.patch
#   ];
#   propagatedBuildInputs = (attrs.propagatedBuildInputs or []) ++
#     [ libgccjit
#     ];
#   buildInputs = attrs.buildInputs ++
#     [ libpng
#       libjpeg
#       libungif
#       libtiff
#       librsvg
#       jansson
#       freetype
#       harfbuzz.dev
#       git
#     ];
#   preConfigure = ''
#     sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure.ac
#     autoreconf
#   '';
#   # configureFlags = attrs.configureFlags ++
#   #   [ "--enable-checking=yes,glyphs"
#   #     "--enable-check-lisp-object-type"
#   #   ];
# });

# emacsHEADPackages   = self.emacsHEADPackagesNg;
# emacsHEADPackagesNg = mkEmacsPackages self.emacsHEAD;

emacsEnv = self.emacs29MacPortEnv;

emacs29Env = myPkgs: pkgs.myEnvFun {
  name = "emacs29";
  buildInputs = [
    (self.emacs29PackagesNg.emacsWithPackages myPkgs)
  ];
};

emacs29MacPortEnv = myPkgs: pkgs.myEnvFun {
  name = "emacs29MacPort";
  buildInputs = [
    (self.emacs29MacPortPackagesNg.emacsWithPackages myPkgs)
  ];
};

}
