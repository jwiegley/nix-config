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
        ;

      withPatches =
        pkg: patches:
        pkg.overrideAttrs (attrs: {
          inherit patches;
        });

      compileEmacsFiles = args: prev.callPackage ./emacs/builder.nix ({ inherit (eself) emacs; } // args);

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

      jobhours =
        if paths.hours != null then
          compileEmacsFiles {
            name = "jobhours";
            src = paths.hours;
          }
        else
          null;

      ########################################################################

      anvil =
        (compileEmacsFiles {
          name = "anvil";
          src = fetchFromGitHub {
            owner = "zawatton";
            repo = "anvil.el";
            rev = "574568a95a2bd8fceca6c9cd3bec0f94ecf0e6a9";
            sha256 = "sha256-z/wYZKkXyE3/7d6MSZ4RJpXcxBGyMdrx6Ndid7Yz5iw=";
            # date = 2026-07-04T05:05:52+00:00;
          };
          # Worker-pool fixes (see the patch header): probe the cached
          # socket path in the stale check instead of re-expanding its
          # basename against the current `server-socket-dir', tell
          # spawned -Q workers where to bind their sockets, and add a
          # spawn grace period so slow-starting workers are not doubled
          # by same-named twin daemons.  lisp/anvil-ext.el in dot-emacs
          # carries equivalent advice overlays for sessions running an
          # unpatched build.
          patches = [
            # Load-bearing order: host-child bindings are rebased against
            # the interrupt-safe host implementation introduced here.
            ./emacs/patches/anvil-issue-53-hang-fixes.patch
            ./emacs/patches/anvil-worker-pool.patch
            ./emacs/patches/anvil-host-child-bindings.patch
            ./emacs/patches/anvil-root-watchdog.patch
            ./emacs/patches/anvil-stdio-at-most-once.patch
            ./emacs/patches/anvil-stdio-no-alternate-editor.patch
          ];
        }).overrideAttrs
          (attrs: {
            # anvil-server-commands.el resolves anvil-stdio.sh (the MCP stdio
            # bridge) next to the installed lisp via locate-library, so it
            # must ship alongside the *.el files.
            installPhase = attrs.installPhase + ''
              install anvil-stdio.sh $out/share/emacs/site-lisp
            '';
          });

      anvil-ide = compileEmacsFiles {
        name = "anvil-ide";
        src = fetchFromGitHub {
          owner = "zawatton";
          repo = "anvil-ide.el";
          rev = "0e6130457ac2bdc6c6db2eebeba67a5223231190";
          sha256 = "sha256-L9heDjSvttZQyCxUq9n104YnhelL8XtivHOl2ln+2aI=";
          # date = 2026-04-27T08:48:09+09:00;
        };
        propagatedBuildInputs = with eself; [
          anvil
        ];
        buildInputs = with eself; [
          anvil
        ];
      };

      ecard = compileEmacsFiles {
        name = "ecard";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "ecard";
          rev = "e79cd68c49466f132142b5ce1a4eaa4fbb47fb8c";
          sha256 = "sha256-2c7xlowQBOZqtqtZ/s2BBvKFX33SheTkFYdKoJhBbR8=";
        };
        preBuild = ''
          rm -f *-test.el *-examples.el ecard-benchmark.el ecard-carddav-mock.el
        '';
      };

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
          rev = "3a126ee54479755408faed10da945dbc2366303b";
          sha256 = "sha256-8Koe6IO2+/HvDb2IE1dc/DY3hGmNWcEMAfz6d0gdT7k=";
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
          rev = "510f579409627c333ef0e9157db713b1004da842";
          sha256 = "sha256-HhWR40j/WFcorp8QttXtOz5yxL1B4JUXL+9IuNpoND0=";
          # date = 2025-07-16T14:21:52-04:00;
        };
        propagatedBuildInputs = [
          (prev.emacs-lsp-booster.override { inherit (eself) emacs; })
        ];
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

      magit-gt = compileEmacsFiles {
        name = "magit-gt";
        src = fetchFromGitHub {
          owner = "ajbt200128";
          repo = "magit-gt";
          rev = "9ae3737a8563ad2b4f4956b39abd3cf3ee4c23b0";
          sha256 = "sha256-yguceZ/OormX+2MhUHZ/QF3xmRJ07LXOBr0XNpjxvA8=";
          # date = 2025-04-09T17:08:09Z;
        };
        # magit-gt does (require 'magit) at top level; the builder runs
        # `emacs -Q`, so magit plus the deps it pulls in at byte-compile
        # time must be listed explicitly to be on the load path.
        buildInputs = with eself; [
          magit
          magit-section
          transient
          with-editor
          dash
          compat
          cond-let
          llama
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
          rev = "fdc5a6f5c2e49c9316dde78185475ce8cdb66d67";
          sha256 = "sha256-yjsjhsBx6CQVDBR9z1rnLoEgWxpOaLC/Rv0vZYw9ji0=";
          # date = 2025-09-29T11:18:24+02:00;
        };
        buildInputs = with eself; [ pg ];
      };

      onepassword-el = compileEmacsFiles {
        name = "onepassword-el";
        src = fetchFromGitHub {
          owner = "justinbarclay";
          repo = "1password.el";
          rev = "8c3e35808ed21332e5eb054a495cce6f0c8f5b25";
          sha256 = "sha256-RC3/fLSdH7H78f2wjXnXoOIi1zIZNG4EW/rBwGEXEz0=";
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
          rev = "5be267d2d92c230b4347e0769f584c71aec53589";
          sha256 = "sha256-N8+ITu25WLtw6sqYxFR2LvfQQCV4ASTYVwDTYN5m/lM=";
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

      wikipedia = compileEmacsFiles {
        name = "wikipedia";
        src = fetchFromGitHub {
          owner = "benthamite";
          repo = "wikipedia";
          rev = "d7219cd453a93b93598a339d20927bdf60eded8d";
          sha256 = "sha256-+gLcdDb3xZJS47dzScBT3ZkR+ZXaUhWt9bZvE1MDO7M=";
          # date = 2026-04-20T14:13:55Z;
        };
        # transient, gptel, and llama are loaded at byte-compile time; the
        # builder runs `emacs -Q` so transitive deps must be listed explicitly.
        buildInputs = with eself; [
          mediawiki
          transient
          gptel
          llama
          compat
          cond-let
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
          rev = "36fe296e016449433fa1213f4b89cb8dc7d4db5e";
          sha256 = "sha256-W2cEtjhoXxAhMxycLAg0qe2Ehpgn1L/m1VcpZu/Trsw=";
          # date = 2025-06-01T11:07:58-07:00;
        };
        buildInputs = with eself; [ gptel ];
      };

      macher = compileEmacsFiles {
        name = "macher";
        src = fetchFromGitHub {
          owner = "kmontag";
          repo = "macher";
          rev = "44950accf782b2ae0a29f48bc85fb4842bc38ab1";
          sha256 = "sha256-FKFHKnhs6GkjUFiF03x/b9kMg4hwgh8Pf0vu55eE3CM=";
          # date = 2025-08-20T19:15:22-07:00;
        };
        buildInputs = with eself; [ gptel ];
      };

      ########################################################################

      # Org 9.8.7 from Savannah, replacing both the Org bundled with Emacs
      # and nixpkgs' GNU ELPA org package. emacsWithPackages puts package
      # site-lisp ahead of Emacs's own lisp, so this shadows the built-in
      # Org everywhere, and every package below listing `org` in its
      # buildInputs byte-compiles against it. This must stay a melpaBuild
      # (not compileEmacsFiles) so packages declaring a versioned
      # dependency on org keep working. A bare git checkout lacks
      # org-version.el and org-loaddefs.el — org.el refuses to load
      # without them — so run Org's own `make autoloads` before
      # package-build assembles the package. The etc/ data files must be
      # installed under etc/ next to the lisp: oc-csl and ox-odt resolve
      # them relative to the installed oc.el/ox-odt.el.
      org = esuper.melpaBuild {
        pname = "org";
        version = "9.8.7";
        src = fetchgit {
          url = "https://git.savannah.gnu.org/git/emacs/org-mode.git";
          rev = "refs/tags/release_9.8.7";
          sha256 = "sha256-7ZmwAkVjEf+a8I9zBE9IMdGdvTdDwM8DXFkG+f1oHZo=";
          # date = 2026-07-04T07:34:28+02:00;
        };
        commit = "cdc16898fd46a30d7187c0a5830b2b898ffbd2de";
        files = ''
          ("lisp/*.el"
           ("etc" "etc/ORG-NEWS")
           ("etc/styles" "etc/styles/*")
           ("etc/csl" "etc/csl/*")
           ("etc/schema" "etc/schema/*"))
        '';
        preBuild = ''
          make autoloads ORGVERSION=9.8.7 GITVERSION=release_9.8.7
        '';
      };

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
          rev = "07094dac902e452d59533e4d01e8177afaa0cfd1";
          sha256 = "sha256-TGuuoaCABgLTHDPfx0/MmHN7JoS4c2M+eAiJ8X3SgiU=";
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
          rev = "10ea878528a24ae9bf6903da198f347d093f2b11";
          sha256 = "sha256-uK0VN0ABA+iOpTMFqXW2vxnWtjp/S7vEVH2s/FS0bus=";
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
          rev = "e6e5fbfcb8beb520141edac647ccb76af9b71df6";
          sha256 = "sha256-0PzJ58nCcRnOldvrAW0Wl2ns1xmH3XbzgmalPyNgOKU=";
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

      ########################################################################
      # Former ~/.emacs.d/lisp git submodules, pinned to the exact revs that
      # were checked out when migrated to Nix (2026-07-07). Packages that
      # exist upstream in MELPA keep their melpaBuild (and autoloads) with
      # only the src swapped; personal/unpublished ones use compileEmacsFiles.

      alert = esuper.alert.overrideAttrs (_: {
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "alert";
          rev = "31fc56855289d0846e73d7ca9b84b628aeac16a0";
          sha256 = "sha256-i4aEOsUTsNKpRrztk0uY9+zxK7QCqUP6+Qc/h7H1AOw=";
        };
      });

      chess = compileEmacsFiles {
        name = "chess";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "emacs-chess";
          rev = "e51e89fa22159988139e5a03dc29ea20e5f9b501";
          sha256 = "sha256-Cdk81K0KU6q7NIJnsD5D8bY+7fCzjQ+h6HhyWFw/vOI=";
        };
      };

      elisp-dev-mcp = esuper.elisp-dev-mcp.overrideAttrs (_: {
        src = fetchFromGitHub {
          owner = "laurynas-biveinis";
          repo = "elisp-mcp-dev";
          rev = "d70a8f38ededefb7e3d11f3e2b519bf754a54d1a";
          sha256 = "sha256-7DewDcG9q61N6aMoGwyUFMkt/HNKf5LGxoocMe73pk4=";
        };
      });

      git-undo = esuper.git-undo.overrideAttrs (_: {
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "git-undo-el";
          rev = "1e94d2dad39ffa168005dee182dde5694416d9c9";
          sha256 = "sha256-EppewewNPWVbQN76LVoebtKu+FOFCnWDhDeUognPmAo=";
        };
      });

      # gptel pinned to the rev formerly checked out in ~/.emacs.d/lisp/gptel,
      # overriding the stock MELPA gptel's src. This MUST stay a melpaBuild
      # (src override, not compileEmacsFiles) so it keeps package.el version
      # metadata: gptel-fn-complete and other gptel-* packages declare a versioned
      # dependency `(gptel "0.9.8")`, which a compileEmacsFiles package (no
      # version) cannot satisfy. The rev's Package-Requires is only transient +
      # compat, so the stock propagatedBuildInputs already suffice.
      gptel = esuper.gptel.overrideAttrs (_: {
        src = fetchFromGitHub {
          owner = "karthink";
          repo = "gptel";
          rev = "ebf0f3d8e9932e0ac6de82542220864cc17f6784";
          sha256 = "sha256-GN9O9leU1CNbB27gVVzzCP8RtaPtZxspnirbxCk+/xU=";
        };
      });

      ledger-mode = esuper.ledger-mode.overrideAttrs (_: {
        src = fetchFromGitHub {
          owner = "ledger";
          repo = "ledger-mode";
          rev = "b43c9d04e03048763cf37696a63ee2232ac88567";
          sha256 = "sha256-obLSghymXakHNMz5RmCpHZhune1oYLU6ME3GzDpLwOA=";
        };
      });

      mcp-server-lib = esuper.mcp-server-lib.overrideAttrs (_: {
        src = fetchFromGitHub {
          owner = "laurynas-biveinis";
          repo = "mcp-server-lib.el";
          rev = "dec55e6405987250256a81efe92d65bdfa8a140c";
          sha256 = "sha256-zaeysvqWmRGheDkILGI/0F4+lz9VYunHVXJzK4zkhsM=";
        };
      });

      org-autolist = esuper.org-autolist.overrideAttrs (_: {
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "org-autolist";
          rev = "c37e390de4874eab06f6343e6e8dc6cf35f35a8e";
          sha256 = "sha256-ox4DTLEys8OpKdF4TOA//KJByk8DOD65nq3bmpZpp0U=";
        };
      });

      vulpea = compileEmacsFiles {
        name = "vulpea";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "vulpea";
          rev = "ea5d6e551115ed2d6b6aedc14e3aaf2f28283310";
          sha256 = "sha256-okgbgzQRG18yIaxePoTI1uFP6b4j/mB22tYlaEhd0wk=";
        };
        buildInputs = with eself; [
          org-roam
          dash
          s
          f
          compat
          emacsql
          magit-section
          cond-let
          llama
        ];
      };

      claude-code-ide = compileEmacsFiles {
        name = "claude-code-ide";
        src = fetchFromGitHub {
          owner = "manzaltu";
          repo = "claude-code-ide.el";
          rev = "cc508396a09e98931bb588da8542b73fa07733e2";
          sha256 = "sha256-pL5PNnemuXHHhQ0wEqhoagyKNdx+ywb2EEru8XWJ0Lc=";
        };
        buildInputs = with eself; [
          websocket
          web-server
          transient
          flycheck
          compat
          cond-let
          llama
        ];
      };

      copy-code = compileEmacsFiles {
        name = "copy-code";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "emacs-copy-code";
          rev = "0a122d04caab1e1cd903b9287f21884d210b13a2";
          sha256 = "sha256-lgnWn+o6IRKvK9NQfm7bUUe/z2CsZIeKt9tZpSn1phk=";
        };
      };

      gptel-emacs-tools = compileEmacsFiles {
        name = "gptel-emacs-tools";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "gptel-emacs-tools";
          rev = "1ae5e496ea7fe8d3eacf7a6ffe5f5c2eb6a5e756";
          sha256 = "sha256-K0EZc2aei5PNCQ7ZsgLo012xUWGVaqlQZHWAlMPOxeA=";
        };
        buildInputs = with eself; [
          gptel
          transient
          compat
        ];
      };

      gptel-litellm = compileEmacsFiles {
        name = "gptel-litellm";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "gptel-litellm";
          rev = "c6b8603816dd72ab9ee0aaf8c8382f0fcaefe15b";
          sha256 = "sha256-MEkkjI3BFCXkVbc5PidNwqef1KMKZvonTcLCGozjBmA=";
        };
        buildInputs = with eself; [
          gptel
          transient
          compat
          uuidgen
        ];
      };

      gptel-prompts = compileEmacsFiles {
        name = "gptel-prompts";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "gptel-prompts";
          rev = "be29a9aa471e5f398cb5e1c2ce9f40a9f2b36281";
          sha256 = "sha256-a853fJjP4O2Jn7UPHI00W3AcUEDXShoePeE2aO3C4kw=";
        };
        buildInputs = with eself; [
          gptel
          transient
          compat
        ];
      };

      gptel-rag = compileEmacsFiles {
        name = "gptel-rag";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "gptel-rag";
          rev = "eadf31e78ffcb2923eacb85492e681755035e462";
          sha256 = "sha256-aA9HjDfxwmxRMdMWjCpjNNaCpuJWKB4wIu/kGTsw00c=";
        };
        buildInputs = with eself; [
          gptel
          transient
          compat
        ];
      };

      hash-store = compileEmacsFiles {
        name = "hash-store";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "hash-store";
          rev = "2074c01f051733600e94b26809f4c3ba1f26086e";
          sha256 = "sha256-bKjiStot9Plja5I+ZpOVQOlx4StxGlviMWU7YPuPHEg=";
        };
      };

      haskell-config = compileEmacsFiles {
        name = "haskell-config";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "haskell-config";
          rev = "9f42695fc99aeb6251e5394103d97ad00e2bf0dc";
          sha256 = "sha256-uj11pONsDv5L8xAKv5kEWNbbPus+4TmpDrtf91lb8Sc=";
        };
        buildInputs = with eself; [
          proof-general
        ];
      };

      initsplit = compileEmacsFiles {
        name = "initsplit";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "initsplit";
          rev = "e488e8f95661a8daf9c66241ce58bb6650d91751";
          sha256 = "sha256-+OXdyAFCLwQhpyCsu94lAhVEeCwi7hc/xcmC3frtc+M=";
        };
      };

      llm-tool-collection = compileEmacsFiles {
        name = "llm-tool-collection";
        src = fetchFromGitHub {
          owner = "skissue";
          repo = "llm-tool-collection";
          rev = "b9fd45bedf3e0fb07d289730991199ae18785157";
          sha256 = "sha256-40BSMoM25tdgXeH5+labLYqCPCK4SEuAWovOeJxnzNo=";
        };
      };

      loeb = compileEmacsFiles {
        name = "loeb";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "emacs-loeb";
          rev = "5e66a400102e2ae3e958dc6922436019ffaa18c9";
          sha256 = "sha256-ajiNxKP8ycjQ1JufqM9Fu6mFW95Jbn1Y3pJzvO7ru8Y=";
        };
      };

      lzw = compileEmacsFiles {
        name = "lzw";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "emacs-lzw";
          rev = "27f4c8ed656dba8d90764a1669b0abe25d52d327";
          sha256 = "sha256-llQvVnsRkLU/fHu5Yi/HLSdR4Qtq6Uqck+kVlxpQ5dc=";
        };
      };

      machines =
        (compileEmacsFiles {
          name = "machines";
          src = fetchFromGitHub {
            owner = "jwiegley";
            repo = "machines";
            rev = "ba64481bfbe20b76ad1df89f2d5b116bdb81c78e";
            sha256 = "sha256-R6eoASGGXIcu4CWiX+KPPF93juFcRG2eNJFNFRvtlso=";
          };
          # m-gptel.el (require 'gptel-curl) no longer compiles: gptel dropped
          # gptel-curl.el, so this optional integration is dead in the source
          # checkout too (nothing loads it — m.el is the only feature). Ship it
          # as source only, matching the submodule's stale-.elc behaviour.
          preBuild = ''
            rm -f m-gptel.el
          '';
        }).overrideAttrs
          (attrs: {
            installPhase = attrs.installPhase + ''
              install $src/m-gptel.el $out/share/emacs/site-lisp
            '';
          });

      magit-ai = compileEmacsFiles {
        name = "magit-ai";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "magit-ai";
          rev = "3f7fce8ebb0ff5f2bbfaaea502231b3c62c1bbe2";
          sha256 = "sha256-AL3ehGl6+b/mQXBRt8RN12xPfJYZ8V45xECETFO1ksc=";
        };
        buildInputs = with eself; [
          magit
          transient
          compat
          dash
          magit-section
          with-editor
          llama
          cond-let
        ];
      };

      ob-gptel = compileEmacsFiles {
        name = "ob-gptel";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "ob-gptel";
          rev = "71584eb30e8317cf36104cec78b6d53c4433cae7";
          sha256 = "sha256-cSbhEeAOitGbbq5Ep8axypALc0ueuVKwk/uIfrXaG1g=";
        };
        buildInputs = with eself; [
          gptel
          transient
          compat
          pending
          aio
        ];
      };

      org-agenda-overlay = compileEmacsFiles {
        name = "org-agenda-overlay";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "org-agenda-overlay";
          rev = "a8e6a0052e91e3a8582fd073436b005711a10307";
          sha256 = "sha256-tsCH2TGz+BfV2uMC17LPktemgcHdlJmZ/f1kN/HkE7Y=";
        };
      };

      org-context = compileEmacsFiles {
        name = "org-context";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "org-context";
          rev = "de0da4e8f000d7a9078d056749c3b8ebfa6b6547";
          sha256 = "sha256-zsH6dOMbE+hdWFOY6rJmDegQhlu+pu42nOX9DRnvLl4=";
        };
      };

      org-devonthink = compileEmacsFiles {
        name = "org-devonthink";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "org-devonthink";
          rev = "37314ea676f1349125efbe89a890a586298b1687";
          sha256 = "sha256-UTY2PnYnT3GAQWBf7WH8Djl6llTjj+ip5kCuvlhZ5Iw=";
        };
        buildInputs = with eself; [
          org-roam
          dash
          s
          f
          compat
          emacsql
          magit-section
          cond-let
          llama
        ];
      };

      org-drafts = compileEmacsFiles {
        name = "org-drafts";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "org-drafts";
          rev = "b9302b746fcfce7365ec525a63112700999baa6e";
          sha256 = "sha256-HaeAK4Vq+A38k6d0xoz1gU1zFtAN0EMWk/MwOzPpTVQ=";
        };
        buildInputs = with eself; [
          copy-as-format
          pretty-hydra
          hydra
          s
          dash
          lv
        ];
      };

      org-hash = compileEmacsFiles {
        name = "org-hash";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "org-hash";
          rev = "53a7474d93e0fad888538fc51eb0ebf9cfa7b20d";
          sha256 = "sha256-34PW7WQOLEZN4SvHXS1x7i3Q2IvhwZKhK2cXxNOGxYQ=";
        };
      };

      org-table-loeb = compileEmacsFiles {
        name = "org-table-loeb";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "org-table-loeb";
          rev = "f90f334bfe77470f7cb0d945231c04de637ce11e";
          sha256 = "sha256-9XyQnYiAEjl7UW7IAMWLnSQoaauwZLa4d07F+go0kAE=";
        };
        preBuild = ''
          rm -f test-*.el *-test*.el
        '';
      };

      org-wiki = compileEmacsFiles {
        name = "org-wiki";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "org-wiki";
          rev = "1c8f21ef5eed00c744199d225bb902f064b50a70";
          sha256 = "sha256-yOss7m6a5Gbfot/4SzqhhuHMwbkbNAgHJ8r9xNM/Evk=";
        };
        buildInputs = with eself; [
          mcp-server-lib
          org-roam
          org-ql
          dash
          s
          f
          compat
          emacsql
          magit-section
          peg
          ts
        ];
      };

      pending = compileEmacsFiles {
        name = "pending";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "pending";
          rev = "b3192937905bdcfff3d3eed0b94aabae5bbfbc14";
          sha256 = "sha256-pQSlOF+MI/xBOifenI0XyIXc58fHetH1ybQTj3BX/Yo=";
        };
        buildInputs = with eself; [
          aio
        ];
      };

      pl = compileEmacsFiles {
        name = "pl";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "emacs-pl";
          rev = "c5ee5646a49efd3a27f78ba6e139067fbd67f99d";
          sha256 = "sha256-OAwJzXoIonmEIOdL6v+Lq8qlsUTCivKFm+qs5WDNk9w=";
        };
      };

      springboard = compileEmacsFiles {
        name = "springboard";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "springboard";
          rev = "012c44daa6d487d29fe265d92082fda7c2e03c6c";
          sha256 = "sha256-AGx373prCFCrfsIE5gMMe/2Jf/Mc+PZubDPMpnFgXoo=";
        };
        buildInputs = with eself; [
          helm
          async
          wfnames
          ivy
          helm-core
        ];
      };

      stock-quote = compileEmacsFiles {
        name = "stock-quote";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "stock-quote";
          rev = "8e3fc578fcbb8468104a43438c748e2a4f9ee0d6";
          sha256 = "sha256-qgHToyKuJd1MwkgDMIBqaQOrdifbm+Cj1yV8WjIJ6nk=";
        };
      };

      vulpea-field = compileEmacsFiles {
        name = "vulpea-field";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "vulpea-field";
          rev = "dfb6d9032d771fd9bd87f35db8fa0af6c7355931";
          sha256 = "sha256-1xKPIDHSyi0yOvyUfjxGXA1gobg2K1hUqtJlGgor3vg=";
        };
        buildInputs = with eself; [
          vulpea
          org-roam
          dash
          s
          f
          compat
          emacsql
          magit-section
          cond-let
          llama
        ];
      };

      wombag = compileEmacsFiles {
        name = "wombag";
        src = fetchFromGitHub {
          owner = "karthink";
          repo = "wombag";
          rev = "62f8e7ae8c8f26a834a66fb5a179693bd8078839";
          sha256 = "sha256-YhjOXbqfnlwoZ6Hu/DLDTz7ErWcWALiYlvmQMCmJj0k=";
        };
        buildInputs = with eself; [
          compat
          emacsql
          request
        ];
      };

      z3 = compileEmacsFiles {
        name = "z3";
        src = fetchFromGitHub {
          owner = "jwiegley";
          repo = "emacs-z3";
          rev = "ce2d19772ac8fd8e1d17238238dc9a152eddc25f";
          sha256 = "sha256-wU556v+oarKug/Sx86HjLglOt48RfkBMNUwR7xre5Z8=";
        };
      };

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
  emacs = if prev.stdenv.isDarwin then final.emacs30-macport else final.emacs30;
  emacsPackages =
    if prev.stdenv.isDarwin then final.emacs30MacPortPackages else final.emacs30Packages;
  emacsPackagesNg =
    if prev.stdenv.isDarwin then final.emacs30MacPortPackagesNg else final.emacs30PackagesNg;
  emacsEnv = if prev.stdenv.isDarwin then final.emacs30MacPortEnv else final.emacs30Env;

}
// prev.lib.optionalAttrs prev.stdenv.isDarwin {

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

}
// {

  ##########################################################################

  emacs30 =
    (prev.emacs30.override {
      withImageMagick = true;
      withNativeCompilation = true;
    }).overrideAttrs
      (attrs: {
        configureFlags = attrs.configureFlags ++ [ "--disable-gc-mark-trace" ];
        patches =
          attrs.patches ++ prev.lib.optionals prev.stdenv.isDarwin [ ./emacs/patches/nsthread.patch ];
      });
  emacs30Packages = final.emacs30PackagesNg;
  emacs30PackagesNg = mkEmacsPackages final.emacs30;

  emacs30Env =
    myPkgs:
    prev.myEnvFun {
      name = "emacs30";
      buildInputs = [ (final.emacs30PackagesNg.emacsWithPackages myPkgs) ];
    };

}
// prev.lib.optionalAttrs (paths.emacs-src != null) {

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
      (attrs: {
        version = "31.0.50";
        env = {
          NATIVE_FULL_AOT = "1";
          LIBRARY_PATH = lib.concatStringsSep ":" libGccJitLibraryPaths;
        };
        src = paths.emacs-src;
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
