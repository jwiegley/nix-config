self: pkgs:

let
  myEmacsPackageOverrides = eself: esuper:
    let
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub fetchzip stdenv lib;
      inherit (stdenv) mkDerivation;

      withPatches = pkg: patches:
        pkg.overrideAttrs(attrs: { inherit patches; });

      compileEmacsFiles = args:
        pkgs.callPackage ./emacs/builder.nix ({
          inherit (eself) emacs;
        } // args);

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
    rs-gnus-summary = compileLocalFile "rs-gnus-summary.el";
    supercite       = compileLocalFile "supercite.el";

    company-coq   = withPatches esuper.company-coq   [ ./emacs/patches/company-coq.patch ];
    magit         = withPatches esuper.magit         [ ./emacs/patches/magit.patch ];

    ########################################################################

    ascii = compileEmacsWikiFile {
      name = "ascii.el";
      sha256 = "1ijpnk334fbah94vm7dkcd2w4zcb0l7yn4nr9rwgpr2l25llnr0f";
      # date = 2021-03-26T13:22:06-0700;
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

    erc-highlight-nicknames = compileEmacsWikiFile {
      name = "erc-highlight-nicknames.el";
      sha256 = "01r184q86aha4gs55r2vy3rygq1qnxh1bj9qmlz97b2yh8y17m50";
      # date = 2021-03-26T13:22:24-0700;
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

    jobhours = compileEmacsFiles {
      name = "jobhours";
      src = /Users/johnw/src/hours;
    };

    ########################################################################

    awesome-tray = compileEmacsFiles {
      name = "awesome-tray";
      src = fetchFromGitHub {
        owner = "manateelazycat";
        repo = "awesome-tray";
        rev = "3e0fda76a2bcf370a6126a2c80e3cd529225009a";
        sha256 = "0zdks35fpf4n3nkgf83224aqlqyw1i7vcib688m1damcb59v0xyd";
        # date = 2025-05-16T23:59:51+08:00;
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

    doxymacs = compileEmacsFiles {
      name = "doxymacs";
      src = fetchFromGitHub {
        owner = "dpom";
        repo = "doxymacs";
        rev = "a843eebe0f53c939d9792df3bbfca95661d31ece";
        sha256 = "0py60glqgrx5sw6nmsskq6lhys01n9972gcq9vyq3hcwqvccp1cq";
        # date = 2017-06-25T20:09:07+03:00;
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
        rev = "1260d2f7dd18619b42359aa3e1ba6871aa52fd26";
        sha256 = "0b8pknnkyzqmi7b8ms27dzcbcx87cn2m8m160v18mv6b61c0mq5m";
        # date = 2025-04-28T09:48:37-04:00;
      };
      propagatedBuildInputs = with eself; [
        (pkgs.emacs-lsp-booster.override {
           emacs = eself.emacs;
         })
      ];
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

    # initsplit = compileEmacsFiles {
    #   name = "initsplit";
    #   src = fetchFromGitHub {
    #     owner = "jwiegley";
    #     repo = "initsplit";
    #     rev = "e488e8f95661a8daf9c66241ce58bb6650d91751";
    #     sha256 = "1qvkxpxdv0n9qlzigvi25iw485824pgbpb10lwhh8bs2074dvrgq";
    #     # date = 2015-03-21T23:29:07-05:00;
    #   };
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

    pgmacs = compileEmacsFiles {
      name = "pgmacs";
      src = fetchFromGitHub {
        owner = "emarsden";
        repo = "pgmacs";
        rev = "cf3c0e48e46d3eb822c0157e03209e4f42e2faa9";
        sha256 = "1rczdbvjfkxx6d12ndrpwhm0vmb08l192vi5xl713qimj06pi64r";
        # date = 2025-06-08T14:59:52+02:00;
      };
      buildInputs = with eself; [ pg ];
    };

    onepassword-el = compileEmacsFiles {
      name = "onepassword-el";
      src = fetchFromGitHub {
        owner = "justinbarclay";
        repo = "1password.el";
        rev = "bccba07435682d2925ac357f60568acc99c72ae1";
        sha256 = "0fllkzqc0ifsbfdqff89agzdn4mky163yq341midnw5k4pcvsq26";
        # date = 2025-06-21T15:35:42-07:00;
      };
      buildInputs = with eself; [ aio ];
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

    typo = compileEmacsFiles {
      name = "typo";
      src = fetchFromGitHub {
        owner = "jorgenschaefer";
        repo = "typoel";
        rev = "173ebe4fc7ac38f344b16e6eaf41f79e38f20d57";
        sha256 = "09835zlfzxby5lpz9njl705nqc2n2h2f7a4vpcyx89f5rb9qhy68";
        # date = 2020-07-06T19:14:52+02:00;
      };
    };

    ultra-scroll-mac = compileEmacsFiles {
      name = "ultra-scroll-mac";
      src = fetchFromGitHub {
        owner = "jdtsmith";
        repo = "ultra-scroll-mac";
        rev = "3dd35e9a2aa327ddf889bd0f3341a81d3215862b";
        sha256 = "1nl2w43napga88xkvs2vznrfjzncsiaphb0aiks0kdzas6597qmv";
        # date = 2025-06-21T12:45:38-04:00;
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

    gptel-got = compileEmacsFiles {
      name = "gptel-got";
      src = fetchgit {
        url = https://codeberg.org/bajsicki/gptel-got.git;
        rev = "dc40c13c125cedbd55ad6425fbb7e95930099cc7";
        sha256 = "1v5bxkmpsib2wk76sqvgq3718fk699g5d7nrps481gnw85hc1ffd";
        # date = 2025-05-26T19:51:24+02:00;
      };
      buildInputs = with eself; [ gptel ];
      preBuild = ''
        rm -f gptel-got-qol.el
      '';
    };

    gptel-quick = compileEmacsFiles {
      name = "gptel-quick";
      src = fetchFromGitHub {
        owner = "karthink";
        repo = "gptel-quick";
        rev = "495b5e0b5348dbced1448bd12cbf8847e30b5175";
        sha256 = "1k4n0qmaw4cbybw502wnn1mv2pr9giaickq830ly6bxrc5wz7jn4";
        # date = 2025-06-01T11:07:58-07:00;
      };
      buildInputs = with eself; [ gptel ];
    };

    macher = compileEmacsFiles {
      name = "macher";
      src = fetchFromGitHub {
        owner = "kmontag";
        repo = "macher";
        rev = "a1adeb063a5a54787abf5b75f9d70a53da9fa1a2";
        sha256 = "0lp5cxs2ayg7nbriplrddkyfpaby85fysz6ra3mb1h8168b5x4gh";
        # date = 2025-06-18T13:33:44+02:00;
      };
      buildInputs = with eself; [ gptel ];
    };

    ########################################################################

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

    org-checklist = compileEmacsFiles {
      name = "org-checklist.el";
      src = fetchurl {
        url = "https://git.sr.ht/~bzg/org-contrib/blob/master/lisp/org-checklist.el";
        sha256 = "03z9cklpcrnc0s0igi7jxz0aw7c97m9cwz7b1d8nfz29fws25cx9";
        # date = "2025-07-09T20:55:10-0700";
      };
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

    org-margin = compileEmacsFiles {
      name = "org-margin";
      src = fetchFromGitHub {
        owner = "rougier";
        repo = "org-margin";
        rev = "4013b59ff829903a7ab86b95593be71aa5c9b87d";
        sha256 = "13x5568yfqm1lfmy29vcii2bdkjxjygmhslbr0fwgm2xq9rn63yv";
        # date = 2024-01-15T11:05:11+01:00;
      };
      buildInputs = with eself; [
        org
      ];
    };

    org-mem = compileEmacsFiles {
      name = "org-mem";
      src = fetchFromGitHub {
        owner = "meedstrom";
        repo = "org-mem";
        rev = "3ef1012cd7730d47d44fd19084a906f82d739778";
        sha256 = "0r7yv40p6svvcznr6lzfffmj0dypnbsyxj0xvx1p72f75krn0vxh";
        # date = 2025-06-21T23:37:06+02:00;
      };
      buildInputs = with eself; [
        org llama el-job
      ];
    };

    org-node = compileEmacsFiles {
      name = "org-node";
      src = fetchFromGitHub {
        owner = "meedstrom";
        repo = "org-node";
        rev = "5247c1ffaf9d374421dba22bfcd66acb4d304406";
        sha256 = "16inzjqr97ci9ciqkavv7rhg0a3pygcyab1lyzq0rfjpig5fndnc";
        # date = 2025-07-09T13:28:27+02:00;
      };
      buildInputs = with eself; [
        org org-mem llama magit-section el-job
      ];
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

    org-srs = compileEmacsFiles {
      name = "org-srs";
      src = fetchFromGitHub {
        owner = "bohonghuang";
        repo = "org-srs";
        rev = "4874c854ab67c4c0fced3ab38b9b91a6a7d8b0fe";
        sha256 = "0q64b9g3q5gnvcy9x5dzhwpbk0sqr7gzxd2z2q331a5j8ja275j6";
        # date = 2025-06-22T13:07:03+08:00;
      };
      buildInputs = with eself; [ org fsrs ];
    };

    org-table-highlight = compileEmacsFiles {
      name = "org-table-highlight";
      src = fetchFromGitHub {
        owner = "llcc";
        repo = "org-table-highlight";
        rev = "2ca529780bc9c648a6a7583f2e885fd078bdea96";
        sha256 = "1sgw92f14j5sqja1akcyn2i75yi4vh0m7c9gv5wnhnjm8rs9yzyc";
        # date = 2025-06-23T23:57:46+08:00;
      };
      buildInputs = with eself; [ org ];
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

    ox-whatsapp = compileEmacsFiles {
      name = "ox-whatsapp";
      src = fetchFromGitHub {
        owner = "Hugo-Heagren";
        repo = "ox-whatsapp";
        rev = "9cdff80f3f8bb4dd5d70d772d489a8de575561af";
        sha256 = "04r4z0cjv6jrjgyiyjqgiljnr751qqap3mbdjkwm3naf66wa32qr";
        # date = 2024-03-03T14:54:20Z;
      };
    };

    # ########################################################################

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

    # proof-general =
    #   let texinfo = pkgs.texinfo4 ;
    #       texLive = pkgs.texlive.combine {
    #         inherit (pkgs.texlive) scheme-basic cm-super ec;
    #       }; in mkDerivation rec {
    #   name = "emacs-proof-general-${version}";
    #   version = "d4d2465d";

    #   # This is the main branch
    #   src = fetchFromGitHub {
    #     owner = "ProofGeneral";
    #     repo = "PG";
    #     rev = "d4d2465d0184d9c7aab51eeeac407c22b13ae7e7";
    #     sha256 = "0gk1q8dxh7m2jw54h7rn6psmkl5ngr5rw17gv135fc42cihqq882";
    #     # date = "2025-06-09T21:47:52+02:00";
    #   };

    #   # src = /Users/johnw/src/proof-general;

    #   buildInputs = [ eself.emacs ] ++ (with pkgs; [ texinfo perl which ]);

    #   prePatch =
    #     '' sed -i "Makefile" \
    #            -e "s|^\(\(DEST_\)\?PREFIX\)=.*$|\1=$out|g ; \
    #                s|/sbin/install-info|install-info|g"
    #        sed -i '94d' doc/PG-adapting.texi
    #        sed -i '96d' doc/ProofGeneral.texi
    #     '';

    #   meta = {
    #     description = "Proof General, an Emacs front-end for proof assistants";
    #     longDescription = ''
    #       Proof General is a generic front-end for proof assistants (also known as
    #       interactive theorem provers), based on the customizable text editor Emacs.
    #     '';
    #     homepage = http://proofgeneral.inf.ed.ac.uk;
    #     license = lib.licenses.gpl2Plus;
    #     platforms = lib.platforms.unix;
    #   };
    # };
  };

  mkEmacsPackages = emacs:
    pkgs.lib.recurseIntoAttrs
      ((self.emacsPackagesFor emacs).overrideScope (_: super:
         pkgs.lib.fix
           (pkgs.lib.extends
              myEmacsPackageOverrides
              (_: super.elpaPackages //
                  super.melpaPackages //
                  super.manualPackages //
                  {
                    inherit emacs;
                    inherit (super) elpaBuild melpaBuild trivialBuild;
                    inherit (super) melpaPackages;
                  }))));

in {

emacs           = self.emacs30-macport;
emacsPackages   = self.emacs30MacPortPackages;
emacsPackagesNg = self.emacs30MacPortPackagesNg;
emacsEnv        = self.emacs30MacPortEnv;

##########################################################################

emacs30-macport =
  (pkgs.emacs30-macport.override {
    withTreeSitter = false;
    withNativeCompilation = true;
  }).overrideAttrs(attrs: {
    configureFlags = attrs.configureFlags ++ [
      "--disable-gc-mark-trace"
    ];
  });
emacs30MacPortPackages   = self.emacs30MacPortPackagesNg;
emacs30MacPortPackagesNg = mkEmacsPackages self.emacs30-macport;

emacs30MacPortEnv = myPkgs: pkgs.myEnvFun {
  name = "emacs30MacPort";
  buildInputs = [
    (self.emacs30MacPortPackagesNg.emacsWithPackages myPkgs)
  ];
};

##########################################################################

emacs30 =
  (pkgs.emacs30.override {
    withImageMagick = true;
    withNativeCompilation = true;
  }).overrideAttrs(attrs: {
    configureFlags = attrs.configureFlags ++ [
      "--disable-gc-mark-trace"
    ];
    patches = attrs.patches ++ [
      ./emacs/patches/nsthread.patch
    ];
  });
emacs30Packages   = self.emacs30PackagesNg;
emacs30PackagesNg = mkEmacsPackages self.emacs30;

emacs30Env = myPkgs: pkgs.myEnvFun {
  name = "emacs30";
  buildInputs = [
    (self.emacs30PackagesNg.emacsWithPackages myPkgs)
  ];
};

##########################################################################

emacsHEAD = with pkgs;
  let
    libGccJitLibraryPaths =
      [
        "${lib.getLib libgccjit}/lib/gcc"
        "${lib.getLib stdenv.cc.libc}/lib"
      ]
      ++ lib.optionals (stdenv.cc ? cc.lib.libgcc) [
        "${lib.getLib stdenv.cc.cc.lib.libgcc}/lib"
      ]; in
  (emacs30.override {
      withImageMagick = true;
      withNativeCompilation = false;
    }).overrideAttrs(attrs: rec {
  version = "31.0.50";
  env = {
    NATIVE_FULL_AOT = "1";
    LIBRARY_PATH = lib.concatStringsSep ":" libGccJitLibraryPaths;
  };
  src = nix-gitignore.gitignoreSourcePure [] /Users/johnw/src/emacs;
  patches = [
    (builtins.path {
      name = "inhibit-lexical-cookie-warning-67916.patch";
      path = ./emacs/patches/inhibit-lexical-cookie-warning-67916-30.patch;
    })
  ];
  preConfigure = ''
    sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure.ac
    autoreconf
  '';
  env.NIX_CFLAGS_COMPILE = "-g3 -O0";
  configureFlags = attrs.configureFlags ++ [
    "--enable-checking=yes,glyphs"
    "--enable-check-lisp-object-type"
  ];
});

emacsHEADPackages   = self.emacsHEADPackagesNg;
emacsHEADPackagesNg = mkEmacsPackages self.emacsHEAD;

emacsHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "emacsHEAD";
  buildInputs = [
    (self.emacsHEADPackagesNg.emacsWithPackages myPkgs)
  ];
};

}
