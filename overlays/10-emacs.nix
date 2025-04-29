self: pkgs:

let
  myEmacsPackageOverrides = eself: esuper:
    let
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub fetchzip stdenv lib;
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
      sha256 = "1xnxgjd9nrjz16avyn17ryrw9w3pzjvl14y78mjn64a54fbxxjrf";
      # date = 2025-03-19T15:00:25-0700;
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
      sha256 = "00509bv668wq8k0fa65xmlagkgris85g47f62ynqx7a39jgvca3g";
      # date = 2025-03-19T15:00:16-0700;
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
      sha256 = "1ahcshphziqi1hhrhv52jdmqp9q1w1b3qxl007xrjp3nmz0sbdjr";
      # date = 2025-03-19T15:00:32-0700;
    };

    ########################################################################

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

    awesome-tray = compileEmacsFiles {
      name = "awesome-tray";
      src = fetchFromGitHub {
        owner = "manateelazycat";
        repo = "awesome-tray";
        rev = "40d2dde850227c72850dd6275f9a285713b39302";
        sha256 = "00bh9x3shlz1n35xigrhizalcv6jaqlzh9py51rn3f85sdsvrzdi";
        # date = 2025-02-26T00:26:35+08:00;
      };
    };

    bookmark-plus = compileEmacsFiles {
      name = "bookmark-plus";
      src = fetchFromGitHub {
        owner = "emacsmirror";
        repo = "bookmark-plus";
        rev = "c9fe4b4e768f00823310313c086c5940ac68d76a";
        sha256 = "1nw1hlpyg9c072mj2bh3qji02aj9i62k9rlxc59j7sird1bwlcm9";
        # date = 2024-11-19T21:34:59+01:00;
      };
    };

    cape-yasnippet = compileEmacsFiles {
      name = "cape-yasnippet";
      src = fetchFromGitHub {
        owner = "elken";
        repo = "cape-yasnippet";
        rev = "de6446732b106965ea583c9e076770694f7226b8";
        sha256 = "0aa0lv58c2d67z971di7zn98m51kplx5dpj9yd64dskpgx5j7cxg";
        # date = 2025-02-24T10:18:17Z;
      };
      buildInputs = with eself; [ cape yasnippet ];
    };

    casual = compileEmacsFiles {
      name = "casual";
      src = (fetchFromGitHub {
        owner = "kickingvegas";
        repo = "casual";
        rev = "9c476ea12cdff376f508b1199373257d7e9b8715";
        sha256 = "1jqk5jzj6ykijaa39rpyg85s1czwa4q2qdfv077vnv57wfknzvfy";
        # date = "2025-03-14T15:45:19-07:00";
      }) + "/lisp";
    };

    consult-gh = compileEmacsFiles {
      name = "consult-gh";
      src = fetchFromGitHub {
        owner = "armindarvish";
        repo = "consult-gh";
        rev = "e21b9e44c6d241a9a3afc6c45b3e7c37a543a744";
        sha256 = "1qxk12ia5p8qhmvxdy6zz5kb2cz2gmcmn3mg8gz3s823zx0fj4j0";
        # date = 2025-03-09T20:50:01-07:00;
      };
      buildInputs = with eself; [ consult embark ];
    };

    consult-hoogle = compileEmacsFiles {
      name = "consult-hoogle";
      src = fetchgit {
        url = "https://codeberg.org/rahguzar/consult-hoogle.git";
        rev = "384959016022d071464dc6e611e4fcded562834e";
        sha256 = "12kkslb8pgq11gy9wxqaikvd89sf5qkrnjxrla5cgvffc7d35s5w";
        # date = 2025-02-19T12:40:17+05:00;
      };
      buildInputs = with eself; [ consult haskell-mode compat ];
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

    eager-state = compileEmacsFiles {
      name = "eager-state";
      src = fetchFromGitHub {
        owner = "meedstrom";
        repo = "eager-state";
        rev = "a507fea250d57dde4fff2cfeec8a22c3e2841167";
        sha256 = "0l6bj1yhradcv958g1pzkmsmfam9c0r8v8jf8clb90lz3hvvdmfp";
        # date = 2024-08-23T16:09:59+02:00;
      };
    };

    eglot-booster = compileEmacsFiles {
      name = "eglot-booster";
      src = fetchFromGitHub {
        owner = "jdtsmith";
        repo = "eglot-booster";
        rev = "e6daa6bcaf4aceee29c8a5a949b43eb1b89900ed";
        sha256 = "1fz9c0glxpx9wzkwc5w3lgbr82cj7xdlg9n4cm6pwxg489fdmdrw";
        # date = 2024-10-29T00:42:11-07:00;
      };
      propagatedBuildInputs = with eself; [
        (pkgs.emacs-lsp-booster.override {
           emacs = eself.emacs;
         })
      ];
    };

    slack = compileEmacsFiles {
      name = "slack";
      src = fetchFromGitHub {
        owner = "isamert";
        repo = "emacs-slack";
        rev = "e19319e1a1a7f08feb6cf6e5bbc2fac2c954cc08";
        sha256 = "0wk43xadihikcnwqf6ymp3q7rrhlpwjk3lf6s9jkdzv3fv4qr28k";
        # date = 2025-03-25T14:41:25+01:00;
      };
      buildInputs = with eself; [
        alert circe emojify oauth2 request websocket
      ];
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
        rev = "fab7cee16e91c2d8f9c24e2b08e934fa0813a774";
        sha256 = "16zbv5yyz4widwlyilnfpbfbj1c2d0bjvkv09zhbmmd512d11zrv";
        # date = 2023-05-10T06:39:55-04:00;
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

    lasgun = compileEmacsFiles {
      name = "lasgun";
      src = fetchFromGitHub {
        owner = "aatmunbaxi";
        repo = "lasgun.el";
        rev = "fb65580a713c017a0b5229f1dd5664f1464fade4";
        sha256 = "0i468ja05wzr5fb3q6px9nmfpmrqasxda24174czdxz160fgmhsm";
        # date = 2024-09-20T15:03:32-05:00;
      };
      buildInputs = with eself; [ avy multiple-cursors ];
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

    onnx = compileEmacsFiles {
      name = "onnx";
      src = fetchFromGitHub {
        owner = "lepisma";
        repo = "onnx.el";
        rev = "41da80ed670c2e8f26f3523e6a906318654fb1a7";
        sha256 = "06ngwwrqzxsmdlya196716dz8a140fkfn584lif1cn1ygbas4haz";
        # date = 2025-01-16T13:33:35+05:30;
      };
      propagatedBuildInputs = with eself; [ pkgs.onnxruntime ];
    };

    fsrs = compileEmacsFiles {
      name = "fsrs";
      src = fetchFromGitHub {
        owner = "bohonghuang";
        repo = "lisp-fsrs";
        rev = "6e5f8fda3e96f8a28cffa367835dd18497ca7e28";
        sha256 = "08nj5nxsc38gkv60qhcjh99kmc1himnmfj0dfya43if23hb4bzg7";
        # date = 2025-03-24T01:28:52+08:00;
      };
    };

    peval = compileEmacsFiles {
      name = "peval";
      src = fetchFromGitHub {
        owner = "Wilfred";
        repo = "peval";
        rev = "36af7344121d0d7826ae2516dc831fd90c9909ef";
        sha256 = "1xwfbmm08sbf3fcc7viaysl6rsg4dx3wlmyrv0cfncscxg8x1f1c";
        # date = 2017-12-19T22:30:41Z;
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

    ultra-scroll-mac = compileEmacsFiles {
      name = "ultra-scroll-mac";
      src = fetchFromGitHub {
        owner = "jdtsmith";
        repo = "ultra-scroll-mac";
        rev = "b72c507f6702db18d971a6b6bdc692e260f21159";
        sha256 = "0r5yf0m7jbcilzj8sqvlv1f6wl3dyll3hxas3lsg95r5rwslds01";
        # date = 2025-03-12T13:41:19-04:00;
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
        rev = "cbb1641beb799efb994de4cd95e47384fac3fe5d";
        sha256 = "07b18ij10zld5wv5k7f612gkb3y27i653inq3i905va45v1axvqm";
        # date = 2023-05-26T15:48:10+01:00;
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

    whisper = compileEmacsFiles {
      name = "whisper";
      src = fetchFromGitHub {
        owner = "natrys";
        repo = "whisper.el";
        rev = "fc122657bfb8d5faf6aedaefdc1687193f456d1f";
        sha256 = "1kp9cdk71mfv8jzc68mzw9c4f71kgf4f26g8qys2578a9gk3xv2f";
        # date = 2025-02-06T15:43:09+06:00;
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

    gptel = compileEmacsFiles {
      name = "gptel";
      src = fetchFromGitHub {
        owner = "karthink";
        repo = "gptel";
        rev = "118431efeacf0fa995e9d908a593aea6fff927b8";
        sha256 = "0jysn482qw6fwhchpn2lqbjf6j3w0dwq75sjzkdvxqygxpyqym6b";
        # date = 2025-04-23T17:42:05-07:00;
      };
      buildInputs = with eself; [
        transient compat
      ];
      propagatedBuildInputs = with eself; [
        llama
      ];
    };

    gptel-aibo = compileEmacsFiles {
      name = "gptel-aibo";
      src = fetchFromGitHub {
        owner = "dolmens";
        repo = "gptel-aibo";
        rev = "1016eff1eecc4831e26cae73f5b62626dfb3abf0";
        sha256 = "1h5z69rh7kmcx81g7iwz77xn7ylzfrlrfiknp9sb29lqg745drwj";
        # date = 2025-03-18T17:16:05+08:00;
      };
      buildInputs = with eself; [ gptel ];
    };

    gptel-fn-complete = compileEmacsFiles {
      name = "gptel-fn-complete";
      src = fetchFromGitHub {
        owner = "mwolson";
        repo = "gptel-fn-complete";
        rev = "6970dfa5c123f420ab06b99be012a222e792b019";
        sha256 = "0ywf9rzszvjrkqmj9anfnj7qass6ra2yn8szfwmkn7xwyiq2pijw";
        # date = 2025-03-17T14:05:35-04:00;
      };
      buildInputs = with eself; [ gptel ];
    };

    gptel-quick = compileEmacsFiles {
      name = "gptel-quick";
      src = fetchFromGitHub {
        owner = "karthink";
        repo = "gptel-quick";
        rev = "34acd437a7af8a387c14428bd1abdb3cd9e95d9d";
        sha256 = "0k1lf0279lhv0pk5l0i6rhsh05qrnh265ynwdq79dgb8s77glxzw";
        # date = 2025-04-14T12:06:36-07:00;
      };
      buildInputs = with eself; [ gptel ];
    };

    corsair = compileEmacsFiles {
      name = "corsair";
      src = fetchFromGitHub {
        owner = "rob137";
        repo = "corsair";
        rev = "f750a435d6be68f0d75dc5a90f8aa3cb58e8c16a";
        sha256 = "0xwkfv63klpyqkgx1ihwqh1aqyk8yi3z3appygp28q60rybsyiyl";
        # date = 2024-10-18T11:15:58+01:00;
      };
      buildInputs = with eself; [ gptel ];
    };

    agda2-mode = compileEmacsFiles {
      name = "agda2-mode";
      src = (fetchFromGitHub {
        owner = "agda";
        repo = "agda";
        rev = "493001846fbf63a228381e515b61f73b35d7d58f";
        sha256 = "02m5f6rpvxgmypwb3zxh0z3pwmgrkdvk2rixl9jcjzcy05ydykm8";
        # date = 2025-04-24T19:01:55+02:00;
      }) + "/src/data/emacs-mode";
    };

    ########################################################################

    org-HEAD = mkDerivation rec {
      name = "org-mode-${version}";
      version = "9.7.15-src";

      src = ~/src/org-mode;

      buildInputs = with pkgs; [ eself.emacs texinfo git ];

      installPhase = ''
        make install \
             prefix=$out \
             lispdir=$out/share/emacs/site-lisp/org \
             datadir=$out/share/emacs/etc/org
      '';

      inherit (esuper.org) meta;
    };

    org =
      let
        versions = {
          "9.7.27" = "sha256-5r4yOeYxZqe5rKuIGb/WRaZNvfX+3sZyPYqb2DFJXXg=";
          "9.6.30" = "sha256-NzIPaZw8fINmA/G7mu8WBd2b+F2GluGRgaxoH+U7V0A=";
        };
        version = "9.7.27";
      in eself.elpaBuild {
        pname = "org";
        ename = "org";
        inherit version;
        src =
          if version == "9.7.27"
          then fetchurl {
            url = "https://elpa.gnu.org/packages/org-${version}.tar";
            sha256 = versions."${version}";
          }
          else fetchurl {
            name = "org-${version}.tar";
            url = "https://elpa.gnu.org/packages/org-${version}.tar.lz";
            sha256 = versions."${version}";
            downloadToTemp = true;
            postFetch = "${pkgs.lzip}/bin/lzip -dc $downloadedFile > $out";
          };
        meta = {
          homepage = "https://elpa.gnu.org/devel/org.html";
          license = lib.licenses.free;
        };
      };

    delve = compileEmacsFiles {
      name = "delve";
      src = fetchFromGitHub {
        owner = "publicimageltd";
        repo = "delve";
        rev = "9f294f2f09730fbb715a5a30469ce0d15291a3d6";
        sha256 = "1w6rgyj0k5m3g2fg2my7v1kzghbymcy07scrbfhpg7hvcnm65sjx";
        # date = 2024-12-25T20:11:57+01:00;
      };
      buildInputs = with eself; [
        dash org-roam magit-section lister compat emacsql llama
      ];
    };

    elgantt = compileEmacsFiles {
      name = "elgantt";
      src = fetchFromGitHub {
        owner = "legalnonsense";
        repo = "elgantt";
        rev = "23fe6a3dd4f1a991e077f13869fb960b8b29e183";
        sha256 = "18cgmg8pkbji6945kwdw99hb6vvfvvqkavgb8dbcpk657nqbjq28";
        # date = 2024-02-23T22:42:27-05:00;
      };
      buildInputs = with eself; [ org-ql ts s dash ov compat peg ];
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

    org-noter-plus = compileEmacsFiles {
      name = "org-noter-plus";
      src = fetchFromGitHub {
        owner = "dmitrym0";
        repo = "org-noter-plus";
        rev = "f4c318b1bea6a14a20bf82269dc2614dbf15a1cb";
        sha256 = "0lhx8nypzihwasj63qbjbj0dk18bdr8ms1q5aakc5mn6s65jc2n5";
        # date = 2023-02-05T19:06:01-08:00;
      };
      preBuild = ''
        rm emacs-devel.el
        mv modules/*.el .
        mv other/*.el .
      '';
      buildInputs = with eself; [
        avy
        biblio
        biblio-core
        bibtex-completion
        citar
        citeproc
        compat
        dash
        esxml
        f
        hydra
        log4e
        lv
        nov
        org
        org-pdftools
        org-ref
        parsebib
        pdf-tools
        queue
        request
        s
        tablist
      ];
    };

    org-quick-peek = compileEmacsFiles {
      name = "org-quick-peek";
      src = fetchFromGitHub {
        owner = "alphapapa";
        repo = "org-quick-peek";
        rev = "564e39bec72cba7b20c0373b946b8e58afcb1f43";
        sha256 = "0ihm29ib3hbwc91di553x6ajmdbhaqvrwzp1sly7di3mwwsgh0pz";
        # date = 2022-10-05T20:37:38-05:00;
      };
      buildInputs = with eself; [ quick-peek dash s ];
    };

    org-recoll = compileEmacsFiles {
      name = "org-recoll";
      src = fetchFromGitHub {
        owner = "alraban";
        repo = "org-recoll";
        rev = "1e21fbc70b5e31b746257c12d00acba3dcc1dd5c";
        sha256 = "09bixzl8ky7scsahb50wwkdcz335gy257m80z9rpqqhjy6q9023c";
        # date = "2020-06-28T15:19:50-04:00";
      };
      buildInputs = with eself; [ quick-peek dash s ];
    };

    ox-slack = compileEmacsFiles {
      name = "ox-slack";
      src = fetchFromGitHub {
        owner = "masukomi";
        repo = "ox-slack";
        rev = "0c08db7248d12519a64ed7924cf52d25be0c1f6d";
        sha256 = "0sk9vbax5b64dbmqjb41rbs82adb9d71j8sp6i0lmldsv3f8h3pa";
        # date = 2022-09-14T10:19:41-04:00;
      };
      buildInputs = with eself; [ ox-gfm ];
    };

    org-srs = compileEmacsFiles {
      name = "org-srs";
      src = fetchFromGitHub {
        owner = "bohonghuang";
        repo = "org-srs";
        rev = "11c79919edeac26a95a29d2254a8f6dfed526c13";
        sha256 = "15dc27sikfwx5rwilji0rrf9l99aw5w9va2qhz22y0wjnq5kaam3";
        # date = 2025-03-23T16:06:08+08:00;
      };
      buildInputs = with eself; [ org fsrs ];
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

    ########################################################################

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

    # pdf-tools = esuper.pdf-tools.overrideAttrs (old: {
    #   nativeBuildInputs = [
    #     self.autoconf
    #     self.automake
    #     self.pkg-config
    #     self.removeReferencesTo
    #   ];
    #   buildInputs = old.buildInputs ++ [ self.libpng self.zlib self.poppler ];
    #   preBuild = ''
    #     make server/epdfinfo
    #     remove-references-to \
    #       -t ${self.stdenv.cc.libc} \
    #       -t ${self.glib.dev} \
    #       -t ${self.libpng.dev} \
    #       -t ${self.poppler.dev} \
    #       -t ${self.zlib.dev} \
    #       -t ${self.cairo.dev} \
    #       server/epdfinfo
    #   '';
    #   recipe = self.writeText "recipe" ''
    #     (pdf-tools
    #     :repo "politza/pdf-tools" :fetcher github
    #     :files ("lisp/pdf-*.el" "server/epdfinfo"))
    #   '';
    # });

    proof-general =
      let texinfo = pkgs.texinfo4 ;
          texLive = pkgs.texlive.combine {
            inherit (pkgs.texlive) scheme-basic cm-super ec;
          }; in mkDerivation rec {
      name = "emacs-proof-general-${version}";
      version = "e0ec3db2";

      # This is the main branch
      src = fetchFromGitHub {
        owner = "ProofGeneral";
        repo = "PG";
        rev = "e0ec3db200f8ed465ec533b6409e64e3dfb6a9b0";
        sha256 = "00wwc1fr4xb8h44fwi3qayrpm7pippmlyg2gs9373yjn2x0h4hh7";
        # date = "2025-01-29T13:56:02+01:00";
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

    notdeft = esuper.notdeft.overrideAttrs (_: {
      meta = {
        homepage = "https://tero.hasu.is/notdeft/";
        description = "Fork of Deft that uses Xapian as a search engine";
        maintainers = [ lib.maintainers.nessdoor ];
        license = lib.licenses.bsd3;
        platforms = lib.platforms.unix;
      };
    });

    xeft = mkDerivation rec {
      name = "xeft-${version}";
      version = "3.3";

      src = fetchgit {
        url = https://git.sr.ht/~casouri/xeft;
        rev = "32735a2a631fc2957b79cc65ad851546b7d572df";
        sha256 = "1z96d2akm0qnb86cmndnqbblhsl03sfzql26v59jpqfiiamnlnc0";
        # date = 2023-09-13T22:05:28-07:00;
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
    ((self.emacsPackagesFor emacs).overrideScope (_: super:
       pkgs.lib.fix
         (pkgs.lib.extends
            myEmacsPackageOverrides
            (_: super.elpaPackages
             // super.melpaPackages
             // super.manualPackages
             // { inherit emacs;
                  inherit (super) elpaBuild melpaBuild trivialBuild; }))));

in {

emacs             = self.emacs29MacPort;
emacsPackages     = self.emacs29MacPortPackages;
emacsPackagesNg   = self.emacs29MacPortPackagesNg;

emacs29           = pkgs.emacs29;
emacs29Packages   = self.emacs29PackagesNg;
emacs29PackagesNg = mkEmacsPackages self.emacs29;

emacs29MacPort = pkgs.emacs29-macport.overrideAttrs (o: {
  version = "29.4";
  src = pkgs.fetchgit {
    url = "https://bitbucket.org/mituharu/emacs-mac.git";
    rev = "7cc5e67629363d9e98f65e4e652f83bb4e0ee674";
    sha256 = "sha256-Uv0AX0d5JLgxHlBD70OIDOO/ImMA6hH1fs5hCuMxw7c=";
  };
  configureFlags = o.configureFlags ++ [
    "CFLAGS=-DMAC_OS_X_VERSION_MAX_ALLOWED=101201"
    "CFLAGS=-DMAC_OS_X_VERSION_MIN_REQUIRED=101201"
  ];
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
