# overlays/10-emacs.nix
# Purpose: Emacs with MacPort patches, custom packages, and multiple variants
# Dependencies: Uses final for emacs cross-references; uses prev for nixpkgs
# Packages: emacs, emacs30-macport, emacs30, emacsHEAD, emacsPackages, and
#           40+ custom Emacs packages (jobhours, gptel-*, org-*, etc.)
# Note: Uses ./emacs/builder.nix, ./emacs/patches/*, and paths.hours
final: prev:

let
  paths = import ../config/paths.nix { inherit (prev) inputs; };

  myEmacsPackageOverrides =
    eself: esuper:
    let
      inherit (prev)
        fetchurl
        fetchgit
        fetchFromGitHub
        fetchzip
        stdenv
        lib
        ;
      inherit (stdenv) mkDerivation;

      withPatches =
        pkg: patches:
        pkg.overrideAttrs (attrs: {
          inherit patches;
        });

      compileEmacsFiles = args: prev.callPackage ./emacs/builder.nix ({ inherit (eself) emacs; } // args);

      addBuildInputs =
        pkg: inputs:
        pkg.overrideAttrs (attrs: {
          buildInputs = attrs.buildInputs ++ inputs;
        });

      compileLocalFile =
        name:
        compileEmacsFiles {
          inherit name;
          src = ./emacs + ("/" + name);
        };

      fetchFromEmacsWiki = prev.callPackage (
        {
          fetchurl,
          name,
          sha256,
        }:
        fetchurl {
          inherit sha256;
          url = "https://raw.githubusercontent.com/emacsmirror/emacswiki.org/master/" + name;
        }
      );

      compileEmacsWikiFile =
        {
          name,
          sha256,
          buildInputs ? [ ],
          patches ? [ ],
        }:
        compileEmacsFiles {
          inherit name buildInputs patches;
          src = fetchFromEmacsWiki { inherit name sha256; };
        };

    in
    rec {

      edit-env = compileLocalFile "edit-env.el";
      edit-var = compileLocalFile "edit-var.el";
      rs-gnus-summary = compileLocalFile "rs-gnus-summary.el";
      supercite = compileLocalFile "supercite.el";

      company-coq = withPatches esuper.company-coq [ ./emacs/patches/company-coq.patch ];
      magit = withPatches esuper.magit [ ./emacs/patches/magit.patch ];

      ########################################################################

      ascii = compileEmacsWikiFile {
        name = "ascii.el";
        sha256 = "sha256-DmRLaRFU5Pt4TtkS6w8Fi33CRWOznbpJgmo5Msa0V8Y=";
        # date = 2025-10-02T08:31:55-0700;
      };

      col-highlight = compileEmacsWikiFile {
        name = "col-highlight.el";
        sha256 = "0na8aimv5j66pzqi4hk2jw5kk00ki99zkxiykwcmjiy3h1r9311k";
        # date = 2025-10-02T08:31:56-0700;

        buildInputs = with eself; [ vline ];
      };

      crosshairs = compileEmacsWikiFile {
        name = "crosshairs.el";
        sha256 = "0ld30hwcxvyqfaqi80nvrlflpzrclnjcllcp457hn4ydbcf2is9r";
        # date = 2025-10-02T08:31:57-0700;

        buildInputs = with eself; [
          hl-line-plus
          col-highlight
          vline
        ];
      };

      cursor-chg = compileEmacsWikiFile {
        name = "cursor-chg.el";
        sha256 = "1zmwh0z4g6khb04lbgga263pqa51mfvs0wfj3y85j7b08f2lqnqn";
        # date = 2025-10-02T08:31:58-0700;
      };

      erc-highlight-nicknames = compileEmacsWikiFile {
        name = "erc-highlight-nicknames.el";
        sha256 = "01r184q86aha4gs55r2vy3rygq1qnxh1bj9qmlz97b2yh8y17m50";
        # date = 2025-10-02T08:31:59-0700;
      };

      highlight-cl = compileEmacsWikiFile {
        name = "highlight-cl.el";
        sha256 = "0r3kzs2fsi3kl5gqmsv75dc7lgfl4imrrqhg09ij6kq1ri8gjxjw";
        # date = 2025-10-02T08:31:59-0700;
      };

      hl-line-plus = compileEmacsWikiFile {
        name = "hl-line+.el";
        sha256 = "1ns064l1c5g3dnhx5d2sn43w9impn58msrywsgq0bdyzikg7wwh2";
        # date = 2025-10-02T08:32:00-0700;
      };

      popup-ruler = compileEmacsWikiFile {
        name = "popup-ruler.el";
        sha256 = "0fszl969savcibmksfkanaq11d047xbnrfxd84shf9z9z2i3dr43";
        # date = 2025-10-02T08:32:01-0700;
      };

      pp-c-l = compileEmacsWikiFile {
        name = "pp-c-l.el";
        sha256 = "00509bv668wq8k0fa65xmlagkgris85g47f62ynqx7a39jgvca3g";
        # date = 2025-10-02T08:32:02-0700;
      };

      tidy = compileEmacsWikiFile {
        name = "tidy.el";
        sha256 = "0psci55a3angwv45z9i8wz8jw634rxg1xawkrb57m878zcxxddwa";
        # date = 2025-10-02T08:32:03-0700;
      };

      xray = compileEmacsWikiFile {
        name = "xray.el";
        sha256 = "1s25z9iiwpm1sp3yj9mniw4dq7dn0krk4678bgqh464k5yvn6lyk";
        # date = 2025-10-02T08:32:04-0700;
      };

      yaoddmuse = compileEmacsWikiFile {
        name = "yaoddmuse.el";
        sha256 = "1ahcshphziqi1hhrhv52jdmqp9q1w1b3qxl007xrjp3nmz0sbdjr";
        # date = 2025-10-02T08:32:05-0700;
      };

      jobhours = compileEmacsFiles {
        name = "jobhours";
        src = paths.hours;
      };

      ########################################################################

      awesome-tray = compileEmacsFiles {
        name = "awesome-tray";
        src = fetchFromGitHub {
          owner = "manateelazycat";
          repo = "awesome-tray";
          rev = "448366baf76a46bfa280c49c4a57c7a5e53ebbe5";
          sha256 = "sha256-fL66Lp16qb+8sg2k79WU0dZzRMl2ga/n6oNaGljvYgE=";
          # date = 2025-12-24T22:59:47+08:00;
        };
      };

      bookmark-plus = compileEmacsFiles {
        name = "bookmark-plus";
        src = fetchFromGitHub {
          owner = "emacsmirror";
          repo = "bookmark-plus";
          rev = "892cc0a314ef353e800b6ff9da03b0bfd55e4763";
          sha256 = "sha256-1Pd0e+FxYq1bORf+YS3lsrbA25CVH7zrqwPUPNnXVLE=";
          # date = 2025-08-20T23:33:58+02:00;
        };
      };

      consult-omni = compileEmacsFiles {
        name = "consult-omni";
        src = fetchFromGitHub {
          owner = "armindarvish";
          repo = "consult-omni";
          rev = "bdcd5a065340dce9906ac5c5f359906d31877963";
          sha256 = "sha256-vmKKEmZpzHQ8RDbTuoTCWGRypLfMiHrEv9Zw0G6K1pg=";
          # date = "2025-09-27T22:49:03-07:00";
        };
        propagatedBuildInputs = with eself; [
          browser-hist
          elfeed
          ox-gfm
        ];
        buildInputs = with eself; [
          browser-hist
          elfeed
          ox-gfm
          compat
          consult
          consult-gh
          embark
          embark-consult
          markdown-mode
          gptel
          yaml
          s
        ];
        preBuild = ''
          cp sources/*.el .
          rm -f consult-omni-mu4e.el
          rm -f consult-omni-notmuch.el
        '';
      };

      doxymacs = compileEmacsFiles {
        name = "doxymacs";
        src = fetchFromGitHub {
          owner = "dpom";
          repo = "doxymacs";
          rev = "a843eebe0f53c939d9792df3bbfca95661d31ece";
          sha256 = "sha256-mIXL2MacwYH9Tpg9cVKyAWgPqcFT62oN16Xnh+kDxl8=";
          # date = 2017-06-25T20:09:07+03:00;
        };
      };

      eager-state = compileEmacsFiles {
        name = "eager-state";
        src = fetchFromGitHub {
          owner = "meedstrom";
          repo = "eager-state";
          rev = "53282709833021dfbe8605c9eadaa0fffe5da349";
          sha256 = "sha256-XkQKw8Kq5F2OYoVji49GkJGHbR5r39Z/zFk6kxbvRtc=";
          # date = 2024-08-23T16:09:59+02:00;
        };
        buildInputs = with eself; [ llama ];
      };

      eglot-booster = compileEmacsFiles {
        name = "eglot-booster";
        src = fetchFromGitHub {
          owner = "jdtsmith";
          repo = "eglot-booster";
          rev = "cab7803c4f0adc7fff9da6680f90110674bb7a22";
          sha256 = "sha256-xUBQrQpw+JZxcqT1fy/8C2tjKwa7sLFHXamBm45Fa4Y=";
          # date = 2025-07-16T14:21:52-04:00;
        };
        propagatedBuildInputs = with eself; [ (prev.emacs-lsp-booster.override { emacs = eself.emacs; }) ];
      };

      eww-plz = compileEmacsFiles {
        name = "eww-plz";
        src = fetchFromGitHub {
          owner = "9viz";
          repo = "eww-plz.el";
          rev = "c239ee08c594d5b32d73cd44cfd8a58313adc9b5";
          sha256 = "sha256-WZC8LU0Vr3yugqMKc12XMh3E+IsvbzKQa/3hJrgDR04=";
          # date = 2025-02-10T14:44:32+05:30;
        };
        buildInputs = with eself; [ plz ];
      };

      fence-edit = compileEmacsFiles {
        name = "fence-edit";
        src = fetchFromGitHub {
          owner = "aaronbieber";
          repo = "fence-edit.el";
          rev = "fab7cee16e91c2d8f9c24e2b08e934fa0813a774";
          sha256 = "sha256-O/8Qmgil1brgT2DPLRdoggW53LrO0ugpb5GT733Z65s=";
          # date = 2023-05-10T06:39:55-04:00;
        };
      };

      gnus-harvest = compileEmacsFiles {
        name = "gnus-harvest";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "gnus-harvest";
          rev = "29b406e1ed5a934fad0ae9701bbde1b284e4d939";
          sha256 = "sha256-dy3b4JLsvbloAvY5N/y0Ih//Uj6NIYNwmqaFZ9kDJgg=";
          # date = 2018-02-08T11:20:21-08:00;
        };
      };

      indent-shift = compileEmacsFiles {
        name = "indent-shift";
        src = fetchFromGitHub {
          owner = "ryuslash";
          repo = "indent-shift";
          rev = "292993d61d88d80c4a4429aa97856f612e0402b2";
          sha256 = "sha256-v3TVYlZkMEnEj87NWsUoujXG+veE448MXI+J0i9nUI8=";
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
          sha256 = "sha256-VcP6HDDh9/YZOYEI1bpWONfrqk39GjyWK/nzApREhkQ=";
          # date = 2024-09-20T15:03:32-05:00;
        };
        buildInputs = with eself; [
          avy
          multiple-cursors
        ];
      };

      moccur-edit = compileEmacsFiles {
        name = "moccur-edit";
        src = fetchFromGitHub {
          owner = "myuhe";
          repo = "moccur-edit.el";
          rev = "026f5dd4159bd1b68c430ab385757157ba01a361";
          sha256 = "sha256-/YM0gSB3hNBz1m9PzhY7Ev5l0ssSsoX+lR//ZDTOM+I=";
          # date = 2015-03-01T18:04:32+09:00;
        };
        buildInputs = with eself; [ color-moccur ];
      };

      pgmacs = compileEmacsFiles {
        name = "pgmacs";
        src = fetchFromGitHub {
          owner = "emarsden";
          repo = "pgmacs";
          rev = "8c743e5b9667fc39e98781d8a646d9483eea4917";
          sha256 = "sha256-166hwMhfmv6mP/n8ZL1oMVTqO5MW/qGyotdsuquOjYI=";
          # date = 2025-09-29T11:18:24+02:00;
        };
        buildInputs = with eself; [ pg ];
      };

      onepassword-el = compileEmacsFiles {
        name = "onepassword-el";
        src = fetchFromGitHub {
          owner = "justinbarclay";
          repo = "1password.el";
          rev = "bccba07435682d2925ac357f60568acc99c72ae1";
          sha256 = "sha256-RmC92SWzcNtiDWRgP0zwsxLb/lMJOYebW9pFwPCflDo=";
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
          sha256 = "sha256-GPm9loJlsXvZDyIPnAeDVvJ8hXf95J9/uWnnq+JVe2I=";
          # date = 2012-01-28T14:08:32-06:00;
        };
      };

      sky-color-clock = compileEmacsFiles {
        name = "sky-color-clock";
        src = fetchFromGitHub {
          owner = "zk-phi";
          repo = "sky-color-clock";
          rev = "525122ffb94ae4ac160de72c2ee0ade331d2e80a";
          sha256 = "sha256-mLtJZHGgedPqBkaKDeK6Br2m2eKrTMlmcIuczDFLsJQ=";
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
          sha256 = "sha256-MzkD7gPeKbTsoZpM7rY7P5LjuOmT6GA5tFLgBlVRcO8=";
          # date = 2019-06-03T00:38:56-07:00;
        };
      };

      typo = compileEmacsFiles {
        name = "typo";
        src = fetchFromGitHub {
          owner = "jorgenschaefer";
          repo = "typoel";
          rev = "173ebe4fc7ac38f344b16e6eaf41f79e38f20d57";
          sha256 = "sha256-yHiI08rFJdQ9u5uo4wQUVjBsCzhU2vQvLX717+gvAyU=";
          # date = 2020-07-06T19:14:52+02:00;
        };
      };

      ultra-scroll-mac = compileEmacsFiles {
        name = "ultra-scroll-mac";
        src = fetchFromGitHub {
          owner = "jdtsmith";
          repo = "ultra-scroll-mac";
          rev = "08758c6772c5fbce54fb74fb5cce080b6425c6ce";
          sha256 = "sha256-hKgwjs4qZikbvHKjWIJFlkI/4LXR6qovCoTBM5miVr8=";
          # date = 2025-07-25T13:45:38-04:00;
        };
      };

      vcard-mode = compileEmacsFiles {
        name = "vcard-mode";
        src = fetchFromGitHub {
          owner = "dochang";
          repo = "vcard-mode";
          rev = "ab1a2885a5720d7fb02d9b6583ee908ba2260b78";
          sha256 = "sha256-HKjPPcw1bnBHwT+O4F/mciovrh+vpmsJrEjO3lJXhHA=";
          # date = 2019-01-29T00:54:40+08:00;
        };
      };

      vterm-tmux = compileEmacsFiles {
        name = "vterm-tmux";
        src = fetchgit {
          url = "https://codeberg.org/olivermead/vterm-tmux.git";
          rev = "cbb1641beb799efb994de4cd95e47384fac3fe5d";
          sha256 = "07b18ij10zld5wv5k7f612gkb3y27i653inq3i905va45v1axvqm";
          # date = 2023-05-26T15:48:10+01:00;
        };
        buildInputs = with eself; [
          vterm
          multi-vterm
        ];
      };

      word-count-mode = compileEmacsFiles {
        name = "word-count-mode";
        src = fetchFromGitHub {
          owner = "tomaszskutnik";
          repo = "word-count-mode";
          rev = "6267c98e0d9a3951e667da9bace5aaf5033f4906";
          sha256 = "sha256-0ILbae6W3yhwxZ0TW2AaPIyJc2mBktZQA5VfU5vxfN8=";
          # date = 2015-07-16T22:37:17+02:00;
        };
      };

      ########################################################################

      gptel-got = compileEmacsFiles {
        name = "gptel-got";
        src = fetchgit {
          url = "https://codeberg.org/bajsicki/gptel-got.git";
          rev = "a87fb723c30b217b5883208c0784c06e93944ab2";
          sha256 = "0pyv2rjv36drdv4q9q57pyp09zh2x11xw4qh42wqlg59z85qgb2v";
          # date = 2025-06-27T16:25:27+02:00;
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
          rev = "018ff2be8f860a1e8fe3966eec418ad635620c38";
          sha256 = "sha256-7a5+YQifwtVYHP6qQXS1yxA42bVGXmErirra0TrSSQ0=";
          # date = 2025-06-01T11:07:58-07:00;
        };
        buildInputs = with eself; [ gptel ];
      };

      macher = compileEmacsFiles {
        name = "macher";
        src = fetchFromGitHub {
          owner = "kmontag";
          repo = "macher";
          rev = "16672b88967c3ea452d8670285e2ab7fc705ce17";
          sha256 = "sha256-F37OGrSNFM98sjQDlbSW79sCxnrHWZ7MO52O5VtOn4M=";
          # date = 2025-08-20T19:15:22-07:00;
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
          sha256 = "sha256-rheGSlaDbEh473lEyRKzcd83yXBkmqwX1pudFgj5cOE=";
          # date = 2022-02-08T09:29:08-08:00;
        };
      };

      ob-emamux = compileEmacsFiles {
        name = "ob-emamux";
        src = fetchFromGitHub {
          owner = "jackkamm";
          repo = "ob-emamux";
          rev = "397760d24905ef1f00090586ea38556e6f680780";
          sha256 = "sha256-CY9fojI11+Bu4CAK22bMSrhnEV6spOIQttkLZIYTmag=";
          # date = 2019-05-22T22:30:29-07:00;
        };
        buildInputs = with eself; [ emamux ];
      };

      org-checklist = compileEmacsFiles {
        name = "org-checklist.el";
        src = fetchurl {
          url = "https://git.sr.ht/~bzg/org-contrib/blob/master/lisp/org-checklist.el";
          sha256 = "03z9cklpcrnc0s0igi7jxz0aw7c97m9cwz7b1d8nfz29fws25cx9";
          # date = "2025-10-02T08:32:29-0700";
        };
      };

      org-extra-emphasis = compileEmacsFiles {
        name = "org-extra-emphasis";
        src = fetchFromGitHub {
          owner = "QiangF";
          repo = "org-extra-emphasis";
          rev = "bc6119226ebd84e7f2efd429a03601f563c9bb4f";
          sha256 = "sha256-qCgbmBipJF9ZdwPuxyB9sfJVAvzi7pJ9H42ymuE95LE=";
          # date = 2023-12-01T08:29:06+05:30;
        };
      };

      org-margin = compileEmacsFiles {
        name = "org-margin";
        src = fetchFromGitHub {
          owner = "rougier";
          repo = "org-margin";
          rev = "4013b59ff829903a7ab86b95593be71aa5c9b87d";
          sha256 = "sha256-2w9jc8Jd1McdyItqWJ+XXc62RIxsJ+Gro6Fi55EppY8=";
          # date = 2024-01-15T11:05:11+01:00;
        };
        buildInputs = with eself; [ org ];
      };

      org-mem = compileEmacsFiles {
        name = "org-mem";
        src = fetchFromGitHub {
          owner = "meedstrom";
          repo = "org-mem";
          rev = "caeac6ea7e10aa0698bf6c1ba198a8f7c1d63404";
          sha256 = "sha256-Baf0oijikTEvsff2AgN4N+KjPcgVQf0WF0O/3pMQcQg=";
          # date = 2025-10-01T20:50:56+02:00;
        };
        buildInputs = with eself; [
          org
          llama
          el-job
        ];
      };

      org-node = compileEmacsFiles {
        name = "org-node";
        src = fetchFromGitHub {
          owner = "meedstrom";
          repo = "org-node";
          rev = "f9ef31aa212b33b79383c0c749e0003a69e697a2";
          sha256 = "sha256-9tvf9OfoJVV+tYNF/LBLMF0B3oYaj3T2sf5ObBKQo4c=";
          # date = 2025-10-01T20:55:21+02:00;
        };
        buildInputs = with eself; [
          org
          org-mem
          llama
          magit-section
          el-job
        ];
      };

      org-pretty-table = compileEmacsFiles {
        name = "org-pretty-table";
        src = fetchFromGitHub {
          owner = "Fuco1";
          repo = "org-pretty-table";
          rev = "38e4354bbf7a8d08294babd067fac697038119b1";
          sha256 = "sha256-IeHnoB9hpISwuzI+pKiU+5wvGvz9YJrG5amGg6DGgq4=";
          # date = 2023-03-19T15:52:27+01:00;
        };
        buildInputs = with eself; [ org ];
      };

      org-quick-peek = compileEmacsFiles {
        name = "org-quick-peek";
        src = fetchFromGitHub {
          owner = "alphapapa";
          repo = "org-quick-peek";
          rev = "564e39bec72cba7b20c0373b946b8e58afcb1f43";
          sha256 = "sha256-/wL4NOd1xHY81eF+njdWcLUqlemjlNhCYnzBsWISFUY=";
          # date = 2022-10-05T20:37:38-05:00;
        };
        buildInputs = with eself; [
          quick-peek
          dash
          s
        ];
      };

      org-recoll = compileEmacsFiles {
        name = "org-recoll";
        src = fetchFromGitHub {
          owner = "alraban";
          repo = "org-recoll";
          rev = "1e21fbc70b5e31b746257c12d00acba3dcc1dd5c";
          sha256 = "sha256-bAiQsPESYnxz+gDVU4R/ZYzP2uQclAWVZvr4iejvcSU=";
          # date = "2020-06-28T15:19:50-04:00";
        };
        buildInputs = with eself; [
          quick-peek
          dash
          s
        ];
      };

      org-srs = compileEmacsFiles {
        name = "org-srs";
        src = fetchFromGitHub {
          owner = "bohonghuang";
          repo = "org-srs";
          rev = "c0aff45392b1f836fd943467cc266cef50899a44";
          sha256 = "sha256-yV7F0DimnGyAKMQuXVsm3I9dH4t0ZNvTs82pkez9bC8=";
          # date = 2025-09-21T19:33:28+08:00;
        };
        buildInputs = with eself; [
          org
          fsrs
        ];
      };

      org-table-highlight = compileEmacsFiles {
        name = "org-table-highlight";
        src = fetchFromGitHub {
          owner = "llcc";
          repo = "org-table-highlight";
          rev = "62139dfef47d6e44dccc2ae76ea74d7b03d00641";
          sha256 = "sha256-DiW6EBRvAYN1rvLnEAdxMhKen6xlhriqW4s40Z91E6Y=";
          # date = 2025-07-27T13:44:43+08:00;
        };
        buildInputs = with eself; [ org ];
      };

      ox-texinfo-plus = compileEmacsFiles {
        name = "ox-texinfo-plus";
        src = fetchFromGitHub {
          owner = "tarsius";
          repo = "ox-texinfo-plus";
          rev = "1dfe1c01d34a979ce870269d2c964007f50449d5";
          sha256 = "sha256-gDObdPjXweJ1FizpDZwVMxe633W19CFAnvxnOwz44kM=";
          # date = 2022-03-05T23:47:11+01:00;
        };
      };

      ox-whatsapp = compileEmacsFiles {
        name = "ox-whatsapp";
        src = fetchFromGitHub {
          owner = "Hugo-Heagren";
          repo = "ox-whatsapp";
          rev = "9cdff80f3f8bb4dd5d70d772d489a8de575561af";
          sha256 = "sha256-GYuhuDFO2VH5lG3VcRXGoZxsJY0PSx/9k1maLRn4JBM=";
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
      #   version = "9cdff80f";

      #   # This is the main branch
      #   src = fetchFromGitHub {
      #     owner = "ProofGeneral";
      #     repo = "PG";
      #     rev = "f33b478d1144d6828dfa0df7f0d7d48da704ea11";
      #     sha256 = "0dfd4lpsdjhpp73812i4nb3vkphk4ixmnb9zychv7k2ad6cfhh6p";
      #     # date = "2025-09-15T12:38:50+02:00";
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

  mkEmacsPackages =
    emacs:
    prev.lib.recurseIntoAttrs (
      (final.emacsPackagesFor emacs).overrideScope (
        _: super:
        prev.lib.fix (
          prev.lib.extends myEmacsPackageOverrides (
            _:
            super.elpaPackages
            // super.melpaPackages
            // super.manualPackages
            // {
              inherit emacs;
              inherit (super) elpaBuild melpaBuild trivialBuild;
              inherit (super) melpaPackages;
            }
          )
        )
      )
    );

in
{

  # NOTE: Using 'final' for emacs aliases because they reference
  # packages defined in this same overlay
  emacs = final.emacs30-macport;
  emacsPackages = final.emacs30MacPortPackages;
  emacsPackagesNg = final.emacs30MacPortPackagesNg;
  emacsEnv = final.emacs30MacPortEnv;

  ##########################################################################

  emacs30-macport =
    (prev.emacs30-macport.override {
      srcRepo = true;
      withTreeSitter = true;
      withNativeCompilation = true;
    }).overrideAttrs
      (attrs: {
        env = attrs.env // {
          CFLAGS = "-fobjc-arc";
        };
        configureFlags = attrs.configureFlags ++ [ "--disable-gc-mark-trace" ];
        nativeBuildInputs = attrs.nativeBuildInputs ++ [
          prev.autoreconfHook
          prev.autoconf
          prev.automake
          prev.pkg-config
        ];
      });
  emacs30MacPortPackages = final.emacs30MacPortPackagesNg;
  emacs30MacPortPackagesNg = mkEmacsPackages final.emacs30-macport;

  emacs30MacPortEnv =
    myPkgs:
    prev.myEnvFun {
      name = "emacs30MacPort";
      buildInputs = [ (final.emacs30MacPortPackagesNg.emacsWithPackages myPkgs) ];
    };

  ##########################################################################

  emacs30 =
    (prev.emacs30.override {
      withImageMagick = true;
      withNativeCompilation = true;
    }).overrideAttrs
      (attrs: {
        configureFlags = attrs.configureFlags ++ [ "--disable-gc-mark-trace" ];
        patches = attrs.patches ++ [ ./emacs/patches/nsthread.patch ];
      });
  emacs30Packages = final.emacs30PackagesNg;
  emacs30PackagesNg = mkEmacsPackages final.emacs30;

  emacs30Env =
    myPkgs:
    prev.myEnvFun {
      name = "emacs30";
      buildInputs = [ (final.emacs30PackagesNg.emacsWithPackages myPkgs) ];
    };

  ##########################################################################

  emacsHEAD =
    with prev;
    let
      libGccJitLibraryPaths = [
        "${lib.getLib libgccjit}/lib/gcc"
        "${lib.getLib stdenv.cc.libc}/lib"
      ]
      ++ lib.optionals (stdenv.cc ? cc.lib.libgcc) [ "${lib.getLib stdenv.cc.cc.lib.libgcc}/lib" ];
    in
    (emacs30.override {
      withImageMagick = true;
      withNativeCompilation = false;
    }).overrideAttrs
      (attrs: rec {
        version = "31.0.50";
        env = {
          NATIVE_FULL_AOT = "1";
          LIBRARY_PATH = lib.concatStringsSep ":" libGccJitLibraryPaths;
        };
        src = paths.emacsSrc;
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

  emacsHEADPackages = final.emacsHEADPackagesNg;
  emacsHEADPackagesNg = mkEmacsPackages final.emacsHEAD;

  emacsHEADEnv =
    myPkgs:
    prev.myEnvFun {
      name = "emacsHEAD";
      buildInputs = [ (final.emacsHEADPackagesNg.emacsWithPackages myPkgs) ];
    };

}
