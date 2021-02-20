self: pkgs:

let
  myEmacsPackageOverrides = eself: esuper:
    let
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub stdenv;
      inherit (stdenv) lib mkDerivation;

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

    in {

    seq = if esuper.emacs.version != "26.3"
      then mkDerivation rec {
        name = "seq-stub";
        version = "stub";
        src = ./.;
        phases = [ "installPhase" ];
        installPhase = ''
          mkdir $out
          touch $out/.empty
        '';
      }
      else esuper.seq;


    edit-env        = compileLocalFile "edit-env.el";
    edit-var        = compileLocalFile "edit-var.el";
    ox-extra        = compileLocalFile "ox-extra.el";
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
    org-ref       = withPatches esuper.org-ref       [ ./emacs/patches/org-ref.patch ];
    pass          = withPatches esuper.pass          [ ./emacs/patches/pass.patch ];


    ascii = compileEmacsWikiFile {
      name = "ascii.el";
      sha256 = "1ijpnk334fbah94vm7dkcd2w4zcb0l7yn4nr9rwgpr2l25llnr0f";
      # date = 2020-05-17T11:44:27-0700;
    };

    browse-kill-ring-plus = compileEmacsWikiFile {
      name = "browse-kill-ring+.el";
      sha256 = "14118rimjsps94ilhi0i9mwx7l69ilbidgqfkfrm5c9m59rki2gq";
      # date = 2020-05-17T11:44:34-0700;

      buildInputs = with eself; [ browse-kill-ring ];
      patches = [ ./emacs/patches/browse-kill-ring-plus.patch ];
    };

    col-highlight = compileEmacsWikiFile {
      name = "col-highlight.el";
      sha256 = "0na8aimv5j66pzqi4hk2jw5kk00ki99zkxiykwcmjiy3h1r9311k";
      # date = 2020-05-17T11:44:41-0700;

      buildInputs = with eself; [ vline ];
    };

    crosshairs = compileEmacsWikiFile {
      name = "crosshairs.el";
      sha256 = "0032v3ry043wzvbacm16liykc362pza1bc46x37b307bvbv12qlg";
      # date = 2020-05-17T11:45:34-0700;

      buildInputs = with eself; [ hl-line-plus col-highlight vline ];
    };

    cursor-chg = compileEmacsWikiFile {
      name = "cursor-chg.el";
      sha256 = "1zmwh0z4g6khb04lbgga263pqa51mfvs0wfj3y85j7b08f2lqnqn";
      # date = 2020-05-17T11:45:45-0700;
    };

    dired-plus = compileEmacsWikiFile {
      name = "dired+.el";
      sha256 = "12ls86q5mark4dg9za70g67d1n3qgs3456l0kkf0079903m3gjhh";
      # date = 2021-02-15T10:11:40-0800;
    };

    erc-highlight-nicknames = compileEmacsWikiFile {
      name = "erc-highlight-nicknames.el";
      sha256 = "01r184q86aha4gs55r2vy3rygq1qnxh1bj9qmlz97b2yh8y17m50";
      # date = 2020-05-17T11:46:38-0700;
    };

    fetchmail-mode = compileEmacsWikiFile {
      name = "fetchmail-mode.el";
      sha256 = "19lqkc35kgzm07xjpb9nrcayg69qyijn159lak0mg45fhnybf4a6";
      # date = 2020-05-17T11:46:44-0700;
    };

    hexrgb = compileEmacsWikiFile {
      name = "hexrgb.el";
      sha256 = "18hb8brf7x92aidjfgczxangri6rkqq4x5d06lh41193f97rslm8";
      # date = 2020-05-17T11:46:47-0700;
    };

    highlight-cl = compileEmacsWikiFile {
      name = "highlight-cl.el";
      sha256 = "0r3kzs2fsi3kl5gqmsv75dc7lgfl4imrrqhg09ij6kq1ri8gjxjw";
      # date = 2020-05-17T11:46:52-0700;
    };

    hl-line-plus = compileEmacsWikiFile {
      name = "hl-line+.el";
      sha256 = "0crkmjah8i61z6c15sgn2cbpbj8xqfx0py1y84pxkcjh1cj7hx7q";
      # date = 2020-05-17T11:46:53-0700;
    };

    message-x = compileEmacsWikiFile {
      name = "message-x.el";
      sha256 = "05ic97plsysh4nqwdrsl5m9f24m11w24bahj8bxzfdawfima2bkf";
      # date = 2020-05-17T11:46:56-0700;
    };

    palette = compileEmacsWikiFile {
      name = "palette.el";
      sha256 = "149y6bmn0njgq632m9zdnaaw7wrvxvfqndpqlgcizn6dwzixiih6";
      # date = 2020-05-17T11:46:58-0700;

      buildInputs = with eself; [ hexrgb ];
    };

    popup-pos-tip = compileEmacsWikiFile {
      name = "popup-pos-tip.el";
      sha256 = "0dhyzfsl01y61m53iz38a1vcvclr98wamsh0nishw0by1dnlb17x";
      # date = 2020-05-17T11:47:03-0700;

      buildInputs = with eself; [ popup pos-tip ];
    };

    popup-ruler = compileEmacsWikiFile {
      name = "popup-ruler.el";
      sha256 = "0fszl969savcibmksfkanaq11d047xbnrfxd84shf9z9z2i3dr43";
      # date = 2020-05-17T11:47:06-0700;
    };

    pp-c-l = compileEmacsWikiFile {
      name = "pp-c-l.el";
      sha256 = "03mhd8lja71163jg6fj4d4hy2dwb1c5j46sn9yq6m9wz413a4pmd";
      # date = 2020-05-17T11:47:08-0700;
    };

    tidy = compileEmacsWikiFile {
      name = "tidy.el";
      sha256 = "0psci55a3angwv45z9i8wz8jw634rxg1xawkrb57m878zcxxddwa";
      # date = 2020-05-17T11:47:09-0700;
    };

    vline = compileEmacsWikiFile {
      name = "vline.el";
      sha256 = "1ys6928fgk8mswa4gv10cxggir8acck27g78cw1z3pdz5gakbgnj";
      # date = 2020-05-17T11:47:12-0700;
    };

    xray = compileEmacsWikiFile {
      name = "xray.el";
      sha256 = "1s25z9iiwpm1sp3yj9mniw4dq7dn0krk4678bgqh464k5yvn6lyk";
      # date = 2020-05-17T11:47:15-0700;
    };

    yaoddmuse = compileEmacsWikiFile {
      name = "yaoddmuse.el";
      sha256 = "0h3s3mdfz0czgz1cj415k170g7mbbqmsinw0xr7qmk050i154iis";
      # date = 2020-05-17T11:47:17-0700;
    };


    bytecomp-simplify = compileEmacsFiles {
      name = "bytecomp-simplify.el";
      src = fetchurl {
        url = https://download.tuxfamily.org/user42/bytecomp-simplify.el;
        sha256 = "1yq0wqgva8yidyd46cqag0ds0cyzl7q8rpd2cmksp68k4zlsxwyv";
        # date = 2020-05-17T11:47:20-0700;
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
        # date = 2020-05-17T11:47:30-0700;
      };
    };

    tablegen-mode = compileEmacsFiles {
      name = "tablegen-mode.el";
      src = fetchurl {
        url = https://raw.githubusercontent.com/llvm-mirror/llvm/master/utils/emacs/tablegen-mode.el;
        sha256 = "0dy0diiqfz91blrkpbfxc5ky0l7ghkqi72ah7sh9jkrqa8ss7isy";
        # date = 2020-05-17T11:47:31-0700;
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
        rev = "b6a71e8d153ae8b7bc9afed1cf7659765cfc1b0e";
        sha256 = "1nj9dci6wgwc531vigirx70g3nsw33bsh6ni3bq4dl0x1s4zy6gz";
        # date = 2020-02-14T18:53:14+01:00;
      };
    };

    cell-mode = compileEmacsFiles {
      name = "cell-mode";
      src = fetchgit {
        url = http://gitlab.com/dto/cell.el.git;
        rev = "c7094eb2d8101988339b0a95ca7a4d4708901e68";
        sha256 = "00kgish9q8j5l6kg6n80a83a3dpbmkqqm2idqws41gsniyxaa93b";
        # date = 2019-09-15T23:00:16-04:00;
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

    fill-page = compileEmacsFiles {
      name = "fill-page";
      src = fetchFromGitHub {
        owner = "jcs-elpa";
        repo = "fill-page";
        rev = "3bf1fbdf0e8f325ad0fee016e4a11f7343c8c973";
        sha256 = "124ghk48c70xykakwsfdcfli2rk2rn1x057d1ss6yrgb6gp9drs0";
        # date = 2020-10-04T01:04:41+08:00;
      };
    };

    git-undo = compileEmacsFiles {
      name = "git-undo";
      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "git-undo-el";
        rev = "cf31e38e7889e6ade7d2d2b9f8719fd44f52feb5";
        sha256 = "10f9h8dby3ygkjqwizrif7v1wpwc8iqam5bvayahrabs87s0lnbi";
        # date = 2019-12-21T11:05:45-08:00;
      };
    };

    ghub-plus = compileEmacsFiles {
      name = "ghub-plus";
      src = fetchFromGitHub {
        owner = "vermiculus";
        repo = "ghub-plus";
        rev = "b1adef2402d7599911d4dd447a987a0cea04e6fe";
        sha256 = "0bzri6s5mwvgir9smkz68d5cgcf4glpdmcj8dz8rjxziwrg6k5bz";
        # date = 2019-12-29T11:48:21-06:00;
      };
      buildInputs = with eself; [ ghub apiwrap dash graphql treepy ];
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

    gud-lldb = compileEmacsFiles {
      name = "gud-lldb";
      src = fetchFromGitHub {
        owner = "jojojames";
        repo = "gud-lldb";
        rev = "8e68eef3a14f2a372577fd160d38d438a533c6a9";
        sha256 = "19ab404khsiflhczc2xzdhsqrxlhzi90m4b2wzwb5q5mizivl2y6";
        # date = 2017-04-14T17:22:24-07:00;
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
        # date = 2020-05-17T11:48:46-0700;
      };
      buildInputs = with eself; [ ivy ];
    };

    load-time = compileEmacsFiles {
      name = "load-time";
      src = fetchFromGitHub {
        owner = "fniessen";
        repo = "emacs-load-time";
        rev = "9d31686a76e9792bd06e49ff77c662065ded015c";
        sha256 = "0zhrfidcxqfld7y67pysdlcvrprrka9sq8065ygqx5yxjb7mxs32";
        # date = 2014-10-10T16:52:58+02:00;
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

    mmm-mode = compileEmacsFiles {
      name = "mmm-mode";
      src = fetchFromGitHub {
        owner = "purcell";
        repo = "mmm-mode";
        rev = "552d7401c96f756bd55c205c60df2532bf65c919";
        sha256 = "18spmyw96hp08lf2i81ml2gpc97mkhm1zz4sp8rdjqdzppnq5xmh";
        # date = 2020-05-08T06:10:20+03:00;
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
      buildInputs = with eself; [ color-moccur ];
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

    ox-texinfo-plus = compileEmacsFiles {
      name = "ox-texinfo-plus";
      src = fetchFromGitHub {
        owner = "tarsius";
        repo = "ox-texinfo-plus";
        rev = "3ffceac08c4c690399b85598a5d22cf5bb06c405";
        sha256 = "1jqvzdd3cs4fmkfn3qxw0pv9j3xh87pb4wnzy42yrsq3vs6403gl";
        # date = 2020-01-03T13:38:18+01:00;
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
        rev = "d39f3209faee629bbf140277ce897bae16818602";
        sha256 = "0qha6x595bpc149bs8ra5zq0jndqimc6bhxssb8rbdxvpakqq553";
        # date = 2019-11-06T11:53:28+09:00;
      };
      patches = [ ./emacs/patches/sky-color-clock.patch ];
    };

    spinner = compileEmacsFiles {
      name = "spinner";
      src = fetchFromGitHub {
        owner = "Malabarba";
        repo = "spinner.el";
        rev = "d15e7a7b6395be69acda9d6464acc81d3e2ad07d";
        sha256 = "0gyhjpc68gz1wyqf2rycsl8fgv0f2l6f5jx4mw6ma7zchglj95l2";
        # date = 2020-03-19T08:32:10-03:00;
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
      let Agda = pkgs.haskell.lib.dontHaddock self.haskellPackages_8_6.Agda; in
      eself.trivialBuild {
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

    auctex = eself.elpaBuild {
        pname = "auctex";
        ename = "auctex";
        version = "13.0.4";
        src = fetchurl {
          url = "https://elpa.gnu.org/packages/auctex-13.0.4.tar";
          sha256 = "1362dqb8mcaddda9849gqsj6rzlfq18xprddb74j02884xl7hq65";
        };
        packageRequires = with eself; [ cl-lib emacs ];
        meta = {
          homepage = "https://elpa.gnu.org/packages/auctex.html";
          license = lib.licenses.free;
        };
      };

    ebdb = eself.elpaBuild {
        pname = "ebdb";
        ename = "ebdb";
        version = "0.6.22";
        src = fetchurl {
          url = "https://elpa.gnu.org/packages/ebdb-0.6.22.tar";
          sha256 = "0dljl21n6508c7ash7l6zgxhpn2wdfzga0va63d4k9nwnqmkvsgz";
        };
        packageRequires = with eself; [ cl-lib emacs seq ];
        meta = {
          homepage = "https://elpa.gnu.org/packages/ebdb.html";
          license = lib.licenses.free;
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

      buildInputs = [ eself.emacs ] ++ (with pkgs; [ texinfo perl which ]);

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

    lua-mode = esuper.lua-mode.overrideAttrs(attrs: rec {
      name = "lua-mode-${version}";
      version = "20190113.1350";
      src = fetchFromGitHub {
        owner = "immerrr";
        repo = "lua-mode";
        rev = "35b6e4c20b8b4eaf783ccc8e613d0dd06dbd165c";
        sha256 = "1hai6rqjm5py0bp57nhggmj9qigwdj3a46ngacpnjc1qmy9kkgfk";
        fetchSubmodules = true;
        # date = 2020-05-13T23:13:56+02:00;
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
      buildInputs = [ eself.emacs ] ++ (with pkgs; [ texinfo perl which ]);
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
      version = "2020-06-23";

      # This is the main branch
      src = fetchFromGitHub {
        owner = "ProofGeneral";
        repo = "PG";
        rev = "03e427a8f19485e12b2f95387ed3e0bff7cc944c";
        sha256 = "0ykxb4xdsxv2mja620kf61k2l18scs0jdsfsg1kzs2qf4ddjscyn";
        # date = 2020-06-23T19:48:59+02:00;
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

    use-package = eself.melpaBuild {
      pname = "use-package";
      version = "20180127.1411";
      src = ~/src/dot-emacs/lisp/use-package;
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/51a19a251c879a566d4ae451d94fcb35e38a478b/recipes/use-package";
        sha256 = "0d0zpgxhj6crsdi9sfy30fn3is036apm1kz8fhjg1yzdapf1jdyp";
        name = "use-package";
        # date = 2020-05-17T11:51:29-0700;
      };
      packageRequires = with eself; [ emacs bind-key ];
      meta = {
        homepage = "https://melpa.org/#/use-package";
        license = lib.licenses.free;
      };
    };
  };

  mkEmacsPackages = emacs:
    (self.emacsPackagesFor emacs).overrideScope' (self: super:
      pkgs.lib.fix
        (pkgs.lib.extends
           myEmacsPackageOverrides
           (_: super.elpaPackages
            // super.melpaPackages
            // { inherit emacs;
                 inherit (super) melpaBuild trivialBuild; })));

in {

emacs = self.emacs27;
emacsPackagesNg = self.emacs27PackagesNg;

emacs26_base = pkgs.emacs26.override {
  imagemagick = self.imagemagickBig;
  srcRepo = true;
};

# emacs26 = with pkgs; self.emacs26_base.overrideAttrs(attrs: rec {
#   CFLAGS = "-O3 -Ofast -march=native -funroll-loops " + attrs.CFLAGS;
#   buildInputs = attrs.buildInputs ++
#     [ libpng libjpeg libungif libtiff librsvg ];
#   preConfigure = ''
#     sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure
#   '';
# });

# emacs26PackagesNg = mkEmacsPackages self.emacs26;

# emacs26debug = with pkgs;
#   (pkgs.emacs26.override {
#      imagemagick = self.imagemagickBig;
#      srcRepo = true;
#    }).overrideAttrs(attrs: rec {
#   name = "${attrs.name}-debug";
#   CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
#   buildInputs = attrs.buildInputs ++
#     [ libpng libjpeg libungif libtiff librsvg ];
#   preConfigure = ''
#     sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure
#   '';
#   configureFlags = attrs.configureFlags ++
#     [ "--enable-checking=yes,glyphs" "--enable-check-lisp-object-type" ];
# });

# emacs26DebugPackagesNg = mkEmacsPackages self.emacs26debug;

emacs27_base = self.emacs26_base.overrideAttrs(attrs: rec {
  name = "emacs-${version}${versionModifier}";
  version = "27.1"; versionModifier = ".0";
  patches = [ ./emacs/clean-env-27.patch ];
  src = ~/src/emacs;
  # src = pkgs.fetchurl {
  #   url = "mirror://gnu/emacs/pretest/${name}.tar.xz";
  #   sha256 = "1x0z9hfq7n88amd32714g9182nfy5dmz9br0pjqajgq82vjn9qxk";
  # };
});

emacs27 = with pkgs; self.emacs27_base.overrideAttrs(attrs: rec {
  CFLAGS = "-O3 -march=native -funroll-loops " + attrs.CFLAGS;
  buildInputs = attrs.buildInputs ++
    [ libpng libjpeg libungif libtiff librsvg ];
  preConfigure = ''
    sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure || \
    (sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure.ac; autoreconf)
  '';
});

emacs27PackagesNg = mkEmacsPackages self.emacs27;

emacs27debug = with pkgs; self.emacs27_base.overrideAttrs(attrs: rec {
  name = "${attrs.name}-debug";
  CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
  buildInputs = attrs.buildInputs ++
    [ libpng libjpeg libungif libtiff librsvg ];
  preConfigure = ''
    sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure
  '';
  configureFlags = attrs.configureFlags ++
    [ "--enable-checking=yes,glyphs" "--enable-check-lisp-object-type" ];
});

emacs27DebugPackagesNg = mkEmacsPackages self.emacs27debug;

emacsHEAD = with pkgs; self.emacs27_base.overrideAttrs(attrs: rec {
  name = "emacs-${version}${versionModifier}";
  version = "27.1";
  versionModifier = ".0";
  src = ~/src/emacs;
  CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
  patches = [
    # ./emacs/tramp-detect-wrapped-gvfsd.patch
    ./emacs/clean-env.patch
  ];
  buildInputs = attrs.buildInputs ++
    [ libpng libjpeg libungif libtiff librsvg
      jansson freetype harfbuzz.dev git ];
  preConfigure = ''
    sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure.ac
    autoreconf
  '';
  configureFlags = attrs.configureFlags ++
    [ "--enable-checking=yes,glyphs" "--enable-check-lisp-object-type" ];
});

emacsHEADPackagesNg = mkEmacsPackages self.emacsHEAD;

convertForERC = drv: drv.overrideAttrs(attrs: rec {
  name = "erc-${attrs.version}${attrs.versionModifier}";
  appName = "ERC";
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

# emacs26Env = myPkgs: pkgs.myEnvFun {
#   name = "emacs26";
#   buildInputs = [
#     (self.emacs26PackagesNg.emacsWithPackages myPkgs)
#   ];
# };

# emacs26DebugEnv = myPkgs: pkgs.myEnvFun {
#   name = "emacs26-debug";
#   buildInputs = [
#     (self.emacs26DebugPackagesNg.emacsWithPackages myPkgs)
#   ];
# };

emacs27Env = myPkgs: pkgs.myEnvFun {
  name = "emacs27";
  buildInputs = [
    (self.emacs27PackagesNg.emacsWithPackages myPkgs)
  ];
};

emacs27DebugEnv = myPkgs: pkgs.myEnvFun {
  name = "emacs27-debug";
  buildInputs = [
    (self.emacs27DebugPackagesNg.emacsWithPackages myPkgs)
  ];
};

emacsEnv = self.emacs27Env;
emacsDebugEnv = self.emacs27DebugEnv;

}
