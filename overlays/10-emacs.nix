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
    flymake         = compileLocalFile "flymake-1.0.9.el";
    project         = compileLocalFile "project-0.5.3.el";


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
    # org-ref       = withPatches esuper.org-ref       [ ./emacs/patches/org-ref.patch ];
    pass          = withPatches esuper.pass          [ ./emacs/patches/pass.patch ];


    ascii = compileEmacsWikiFile {
      name = "ascii.el";
      sha256 = "1ijpnk334fbah94vm7dkcd2w4zcb0l7yn4nr9rwgpr2l25llnr0f";
      # date = 2021-03-26T13:22:06-0700;
    };

    browse-kill-ring-plus = compileEmacsWikiFile {
      name = "browse-kill-ring+.el";
      sha256 = "14118rimjsps94ilhi0i9mwx7l69ilbidgqfkfrm5c9m59rki2gq";
      # date = 2021-03-26T13:22:09-0700;

      buildInputs = with eself; [ browse-kill-ring ];
      patches = [ ./emacs/patches/browse-kill-ring-plus.patch ];
    };

    col-highlight = compileEmacsWikiFile {
      name = "col-highlight.el";
      sha256 = "0na8aimv5j66pzqi4hk2jw5kk00ki99zkxiykwcmjiy3h1r9311k";
      # date = 2021-03-26T13:22:13-0700;

      buildInputs = with eself; [ vline ];
    };

    crosshairs = compileEmacsWikiFile {
      name = "crosshairs.el";
      sha256 = "1zw9cw1a84gkqln79w71nxn3vizafrl6g9vg5q007k32f181349v";
      # date = 2021-11-23T09:05:34-0800;

      buildInputs = with eself; [ hl-line-plus col-highlight vline ];
    };

    cursor-chg = compileEmacsWikiFile {
      name = "cursor-chg.el";
      sha256 = "1zmwh0z4g6khb04lbgga263pqa51mfvs0wfj3y85j7b08f2lqnqn";
      # date = 2021-03-26T13:22:19-0700;
    };

    dired-plus = compileEmacsWikiFile {
      name = "dired+.el";
      sha256 = "1rpnzgi1f921zmxkljnc8464qjshqlvdhmavls6z4kbdg85x7vc8";
      # date = 2021-11-23T09:05:38-0800;
    };

    erc-highlight-nicknames = compileEmacsWikiFile {
      name = "erc-highlight-nicknames.el";
      sha256 = "01r184q86aha4gs55r2vy3rygq1qnxh1bj9qmlz97b2yh8y17m50";
      # date = 2021-03-26T13:22:24-0700;
    };

    fetchmail-mode = compileEmacsWikiFile {
      name = "fetchmail-mode.el";
      sha256 = "19lqkc35kgzm07xjpb9nrcayg69qyijn159lak0mg45fhnybf4a6";
      # date = 2021-03-26T13:22:25-0700;
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
      # date = 2021-11-23T09:05:46-0800;
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
      # date = 2021-03-26T13:22:40-0700;
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


    bytecomp-simplify = compileEmacsFiles {
      name = "bytecomp-simplify.el";
      src = fetchurl {
        url = https://download.tuxfamily.org/user42/bytecomp-simplify.el;
        sha256 = "1yq0wqgva8yidyd46cqag0ds0cyzl7q8rpd2cmksp68k4zlsxwyv";
        # date = 2021-03-26T13:22:46-0700;
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
        # date = 2021-03-26T13:22:48-0700;
      };
    };

    tablegen-mode = compileEmacsFiles {
      name = "tablegen-mode.el";
      src = fetchurl {
        url = https://raw.githubusercontent.com/llvm-mirror/llvm/master/utils/emacs/tablegen-mode.el;
        sha256 = "0dy0diiqfz91blrkpbfxc5ky0l7ghkqi72ah7sh9jkrqa8ss7isy";
        # date = 2021-03-26T13:22:49-0700;
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
        rev = "478f945f538a2fd2c0fa0d531876b679914b6d85";
        sha256 = "1hz24aldh68vf8ac16gahlkq2v5ic6r7dm8ra8m6k1343ba572rg";
        # date = 2021-09-19T23:50:08+02:00;
      };
    };

    cell-mode = compileEmacsFiles {
      name = "cell-mode";
      src = fetchgit {
        url = "http://gitlab.com/dto/cell.el.git";
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
        rev = "55d96f18c5df9d8fce51fa073d7a12c47a46ac80";
        sha256 = "1chigywld4v2shc7ij6gyxfq0xzwyms5nal85b3yh7km2pim5i8h";
        # date = 2021-02-20T10:15:07-08:00;
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
        rev = "562d6d5118097b4e62f20773fd90d600ab19fb61";
        sha256 = "0v5irns6061qx0madrf2dc1ahkn4j90v8jpx16l69y9i98dh6n5k";
        # date = 2021-09-27T16:32:31+08:00;
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
        # date = 2021-03-26T13:23:13-0700;
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
        rev = "0d00cdf4d02cc166304f6967a20fa22e2eaf208b";
        sha256 = "1drm89pi67khc04816nynslcqdr9xaf6mb85y6aqrrl4sy0zzwxl";
        # date = 2020-09-09T01:36:25+03:00;
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
        rev = "c639aeaac1a6eb150ac0b92a29650c627f891550";
        sha256 = "1i97ayg867fqmc0vqjd7hpj29gzmpl194i82na0bnp1ql4pqxsx0";
        # date = 2021-11-09T17:50:17+01:00;
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

    spinner = compileEmacsFiles {
      name = "spinner";
      src = fetchFromGitHub {
        owner = "Malabarba";
        repo = "spinner.el";
        rev = "bca794fa6f6b007292cdac9b0a850a3711986db5";
        sha256 = "1m872dj1n05mkvgfyiqsbri489vmff5zdmv4xx5qj2s91sp046rl";
        # date = 2021-07-01T18:20:39-03:00;
      };
    };

    slidify-pages = compileEmacsFiles {
      name = "slidify-pages";
      src = fetchFromGitHub {
        owner = "enaeher";
        repo = "slidify-pages";
        rev = "cae96b0e9fcfe0b71330b478e8c5d667c137ddc7";
        sha256 = "0ya7azdx2l63chqidrxv5yd30y0pk9rn85djfdhipq3a493vgdp6";
        # date = 2020-09-18T09:41:40-04:00;
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
      let Agda = pkgs.haskell.lib.dontHaddock self.haskellPackages.Agda; in
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
        version = "13.0.14";
        src = fetchurl {
          url = "https://elpa.gnu.org/packages/auctex-13.0.14.tar";
          sha256 = "1gmqdcg9s6xf8kvzh1j27nbimakd5cy8pwsn0il19l026kxjimr8";
          # date = 2021-09-14T22:25:39-0700;
        };
        packageRequires = with eself; [ cl-lib emacs ];
        meta = {
          homepage = "https://elpa.gnu.org/packages/auctex.html";
          license = lib.licenses.free;
        };
      };

    debbugs = eself.elpaBuild {
        pname = "debbugs";
        ename = "debbugs";
        version = "0.29";
        src = fetchurl {
          url = "https://elpa.gnu.org/packages/debbugs-0.29.tar";
          sha256 = "1bn21d9dr9pb3vdak3v07x056xafym89kdpxavjf4avy6bry6s4d";
          # date = 2021-09-14T22:25:12-0700;
        };
        meta = {
          homepage = "https://elpa.gnu.org/packages/debbugs.html";
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

    # eglot = esuper.eglot.overrideAttrs(attrs: rec {
    #   name = "eglot-${version}";
    #   version = "20210326.1008";
    #   src = fetchFromGitHub {
    #     owner = "joaotavora";
    #     repo = "eglot";
    #     rev = "2fbcab293e11e1502a0128ca5f59de0ea7888a75";
    #     sha256 = "0fsar0ab0wj74jkbgkbigcg4ia6hg574yvqr2wq2s8lw7m22j8c4";
    #     fetchSubmodules = true;
    #     # date = 2021-03-26T10:08:03+00:00;
    #   };
    #   buildInputs = with eself; [ eldoc flymake jsonrpc project xref ];
    # });

    # lua-mode = esuper.lua-mode.overrideAttrs(attrs: rec {
    #   name = "lua-mode-${version}";
    #   version = "20200513.2313";
    #   src = fetchFromGitHub {
    #     owner = "immerrr";
    #     repo = "lua-mode";
    #     rev = "35b6e4c20b8b4eaf783ccc8e613d0dd06dbd165c";
    #     sha256 = "1hai6rqjm5py0bp57nhggmj9qigwdj3a46ngacpnjc1qmy9kkgfk";
    #     fetchSubmodules = true;
    #     # date = 2020-05-13T23:13:56+02:00;
    #   };
    # });

    xref = compileEmacsFiles rec {
      name = "xref";
      src = fetchurl {
        url = "https://elpa.gnu.org/packages/xref-1.1.0.tar";
        sha256 = "1s7pwk09bry4nqr4bc78a3mbwyrxagai2gpsd49x47czy2x7m3ax";
      };
      preBuild = ''
        tar xf xref
        mv xref-1.1.0/*.el .
      '';
    };

    motoko-mode = compileEmacsFiles rec {
      name = "motoko-mode";
      src = fetchFromGitHub {
        owner  = "dfinity";
        repo   = "motoko";
        rev    = "4115ecec5b471fb105f4aa7c7858a4a35d0e3159";
        sha256 = "0145razl5382g9534qmj8i2ifxs43mc7sy0ian8ijgda637fws0b";
        # date = 2021-11-23T00:25:16+00:00;
      };
      preBuild = ''
        cd emacs
      '';
      buildInputs = with eself; [ emacs swift-mode use-package ];
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
      buildInputs = [ eself.emacs ] ++ (with pkgs; [ texinfo perl which ]);
      meta = {
        homepage = "https://elpa.gnu.org/packages/org.html";
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
      version = "2021-03-21";

      # This is the main branch
      src = fetchFromGitHub {
        owner = "ProofGeneral";
        repo = "PG";
        rev = "2376485828bbd6f151897fdac77dab84f360100e";
        sha256 = "14dgqcc6hp6mywl49kmpb3hgl3cwsrmhcjcv4xwqx1kabd9ni3hd";
        # date = 2021-11-23T00:00:45+01:00;
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

    # use-package = eself.melpaBuild {
    #   pname = "use-package";
    #   version = "20210207.1926";
    #   src = ~/src/dot-emacs/lisp/use-package;
    #   inherit (esuper.use-package) recipe;
    #   packageRequires = with eself; [ emacs bind-key ];
    #   meta = {
    #     homepage = "https://melpa.org/#/use-package";
    #     license = lib.licenses.free;
    #   };
    # };
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
                  inherit (super) melpaBuild trivialBuild; }))));

in {

emacs = self.emacs27;

emacsPackagesNg = self.emacs27PackagesNg;
emacsPackages   = self.emacsPackagesNg;

emacs27_base = pkgs.emacs27.override rec {
  imagemagick = self.imagemagickBig;
  srcRepo = true;
  # patches = [ ./emacs/clean-env-27.patch ];
  # src = ~/src/emacs;
};

emacs27 = with pkgs; self.emacs27_base.overrideAttrs(attrs: rec {
  # CFLAGS = "-O3 -march=native -funroll-loops " + attrs.CFLAGS;
  buildInputs = attrs.buildInputs ++
    [ libpng libjpeg libungif libtiff librsvg ];
  preConfigure = ''
    sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure || \
    (sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure.ac; autoreconf)
  '';
});

emacs27PackagesNg = mkEmacsPackages self.emacs27;
emacs27Packages   = self.emacs27PackagesNg;

emacs27debug = with pkgs; self.emacs27_base.overrideAttrs(attrs: rec {
  name = "${attrs.name}-debug";
  # CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
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
  # CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
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
