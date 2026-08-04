# overlays/10-emacs.nix
# Purpose: Emacs with MacPort patches, custom packages, and multiple variants
# Dependencies: Uses final for emacs cross-references; uses prev for nixpkgs
# Packages: emacs, emacs30-macport, emacs30, emacsHEAD, emacsPackages, and
#           40+ custom Emacs packages (jobhours, gptel-*, org-*, etc.)
# Note: Uses ./emacs/builder.nix, ./emacs/patches/*, and hours
{
  hours ? null,
  emacsSrc ? null,
}:
final: prev:

let
  emacsSources = import ../packages/source-catalog.nix "emacs";
  sourceArgs =
    fetcher: name:
    let
      source = emacsSources.${name}.source;
    in
    assert source.fetcher == fetcher;
    source.args;
  githubSource = name: prev.fetchFromGitHub (sourceArgs "fetchFromGitHub" name);
  gitSource = name: prev.fetchgit (sourceArgs "fetchgit" name);
  urlSource = name: prev.fetchurl (sourceArgs "fetchurl" name);

  myEmacsPackageOverrides =
    eself: esuper:
    let
      withPatches =
        pkg: patches:
        pkg.overrideAttrs (_attrs: {
          inherit patches;
        });

      compileEmacsFiles = args: prev.callPackage ./emacs/builder.nix ({ inherit (eself) emacs; } // args);

      compileLocalFile =
        name:
        compileEmacsFiles {
          inherit name;
          src = ./emacs + ("/" + name);
        };

      compileEmacsWikiFile =
        {
          name,
          buildInputs ? [ ],
          patches ? [ ],
        }:
        compileEmacsFiles {
          inherit name buildInputs patches;
          src = urlSource (prev.lib.removeSuffix ".el" name);
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
      };

      col-highlight = compileEmacsWikiFile {
        name = "col-highlight.el";

        buildInputs = with eself; [ vline ];
      };

      crosshairs = compileEmacsWikiFile {
        name = "crosshairs.el";

        buildInputs = with eself; [
          hl-line-plus
          col-highlight
          vline
        ];
      };

      cursor-chg = compileEmacsWikiFile {
        name = "cursor-chg.el";
      };

      erc-highlight-nicknames = compileEmacsWikiFile {
        name = "erc-highlight-nicknames.el";
      };

      highlight-cl = compileEmacsWikiFile {
        name = "highlight-cl.el";
      };

      hl-line-plus = compileEmacsWikiFile {
        name = "hl-line+.el";
      };

      popup-ruler = compileEmacsWikiFile {
        name = "popup-ruler.el";
      };

      pp-c-l = compileEmacsWikiFile {
        name = "pp-c-l.el";
      };

      tidy = compileEmacsWikiFile {
        name = "tidy.el";
      };

      xray = compileEmacsWikiFile {
        name = "xray.el";
      };

      yaoddmuse = compileEmacsWikiFile {
        name = "yaoddmuse.el";
      };

      jobhours =
        if hours != null then
          compileEmacsFiles {
            name = "jobhours";
            src = hours;
          }
        else
          null;

      ########################################################################

      ecard = compileEmacsFiles {
        name = "ecard";
        src = githubSource "ecard";
        preBuild = ''
          rm -f *-test.el *-examples.el ecard-benchmark.el ecard-carddav-mock.el
        '';
      };

      awesome-tray = compileEmacsFiles {
        name = "awesome-tray";
        src = githubSource "awesome-tray";
      };

      bookmark-plus = compileEmacsFiles {
        name = "bookmark-plus";
        src = githubSource "bookmark-plus";
      };

      consult-omni = compileEmacsFiles {
        name = "consult-omni";
        src = githubSource "consult-omni";
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
        src = githubSource "doxymacs";
      };

      eager-state = compileEmacsFiles {
        name = "eager-state";
        src = githubSource "eager-state";
        buildInputs = with eself; [ llama ];
      };

      eglot-booster = compileEmacsFiles {
        name = "eglot-booster";
        src = githubSource "eglot-booster";
        propagatedBuildInputs = [
          (prev.emacs-lsp-booster.override { inherit (eself) emacs; })
        ];
      };

      eww-plz = compileEmacsFiles {
        name = "eww-plz";
        src = githubSource "eww-plz";
        buildInputs = with eself; [ plz ];
      };

      fence-edit = compileEmacsFiles {
        name = "fence-edit";
        src = githubSource "fence-edit";
      };

      gnus-harvest = compileEmacsFiles {
        name = "gnus-harvest";
        src = githubSource "gnus-harvest";
      };

      indent-shift = compileEmacsFiles {
        name = "indent-shift";
        src = githubSource "indent-shift";
        patches = [ ./emacs/patches/indent-shift.patch ];
      };

      lasgun = compileEmacsFiles {
        name = "lasgun";
        src = githubSource "lasgun";
        buildInputs = with eself; [
          avy
          multiple-cursors
        ];
      };

      magit-gt = compileEmacsFiles {
        name = "magit-gt";
        src = githubSource "magit-gt";
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
        src = githubSource "moccur-edit";
        buildInputs = with eself; [ color-moccur ];
      };

      pgmacs = compileEmacsFiles {
        name = "pgmacs";
        src = githubSource "pgmacs";
        buildInputs = with eself; [ pg ];
      };

      onepassword-el = compileEmacsFiles {
        name = "onepassword-el";
        src = githubSource "onepassword-el";
        buildInputs = with eself; [ aio ];
      };

      sdcv-mode = compileEmacsFiles {
        name = "sdcv-mode";
        src = githubSource "sdcv-mode";
      };

      sky-color-clock = compileEmacsFiles {
        name = "sky-color-clock";
        src = githubSource "sky-color-clock";
        patches = [ ./emacs/patches/sky-color-clock.patch ];
      };

      tla-mode = compileEmacsFiles {
        name = "tla-mode";
        src = githubSource "tla-mode";
      };

      typo = compileEmacsFiles {
        name = "typo";
        src = githubSource "typo";
      };

      ultra-scroll-mac = compileEmacsFiles {
        name = "ultra-scroll-mac";
        src = githubSource "ultra-scroll-mac";
      };

      vcard-mode = compileEmacsFiles {
        name = "vcard-mode";
        src = githubSource "vcard-mode";
      };

      vterm-tmux = compileEmacsFiles {
        name = "vterm-tmux";
        src = gitSource "vterm-tmux";
        buildInputs = with eself; [
          vterm
          multi-vterm
        ];
      };

      wikipedia = compileEmacsFiles {
        name = "wikipedia";
        src = githubSource "wikipedia";
        # The `emacs -Q` builder needs compile-time dependencies listed explicitly.
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
        src = githubSource "word-count-mode";
      };

      ########################################################################

      gptel-got = compileEmacsFiles {
        name = "gptel-got";
        src = gitSource "gptel-got";
        buildInputs = with eself; [ gptel ];
        preBuild = ''
          rm -f gptel-got-qol.el
        '';
      };

      gptel-quick = compileEmacsFiles {
        name = "gptel-quick";
        src = githubSource "gptel-quick";
        buildInputs = with eself; [ gptel ];
      };

      macher = compileEmacsFiles {
        name = "macher";
        src = githubSource "macher";
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
        inherit (emacsSources.org) version;
        src = gitSource "org";
        inherit (emacsSources.org) commit;
        files = ''
          ("lisp/*.el"
           ("etc" "etc/ORG-NEWS")
           ("etc/styles" "etc/styles/*")
           ("etc/csl" "etc/csl/*")
           ("etc/schema" "etc/schema/*"))
        '';
        preBuild = ''
          make autoloads ORGVERSION=${emacsSources.org.version} GITVERSION=release_${emacsSources.org.version}
        '';
      };

      org-annotate = compileEmacsFiles {
        name = "org-annotate";
        src = githubSource "org-annotate";
      };

      ob-emamux = compileEmacsFiles {
        name = "ob-emamux";
        src = githubSource "ob-emamux";
        buildInputs = with eself; [ emamux ];
      };

      org-checklist = compileEmacsFiles {
        name = "org-checklist.el";
        src = urlSource "org-checklist";
      };

      org-extra-emphasis = compileEmacsFiles {
        name = "org-extra-emphasis";
        src = githubSource "org-extra-emphasis";
      };

      org-margin = compileEmacsFiles {
        name = "org-margin";
        src = githubSource "org-margin";
        buildInputs = with eself; [ org ];
      };

      org-mem = compileEmacsFiles {
        name = "org-mem";
        src = githubSource "org-mem";
        buildInputs = with eself; [
          org
          llama
          el-job
        ];
      };

      org-node = compileEmacsFiles {
        name = "org-node";
        src = githubSource "org-node";
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
        src = githubSource "org-pretty-table";
        buildInputs = with eself; [ org ];
      };

      org-quick-peek = compileEmacsFiles {
        name = "org-quick-peek";
        src = githubSource "org-quick-peek";
        buildInputs = with eself; [
          quick-peek
          dash
          s
        ];
      };

      org-recoll = compileEmacsFiles {
        name = "org-recoll";
        src = githubSource "org-recoll";
        buildInputs = with eself; [
          quick-peek
          dash
          s
        ];
      };

      org-srs = compileEmacsFiles {
        name = "org-srs";
        src = githubSource "org-srs";
        buildInputs = with eself; [
          org
          fsrs
        ];
      };

      org-table-highlight = compileEmacsFiles {
        name = "org-table-highlight";
        src = githubSource "org-table-highlight";
        buildInputs = with eself; [ org ];
      };

      ox-texinfo-plus = compileEmacsFiles {
        name = "ox-texinfo-plus";
        src = githubSource "ox-texinfo-plus";
      };

      ox-whatsapp = compileEmacsFiles {
        name = "ox-whatsapp";
        src = githubSource "ox-whatsapp";
      };

      ########################################################################
      # Former ~/.emacs.d/lisp git submodules, pinned to the exact revs that
      # were checked out when migrated to Nix (2026-07-07). Packages that
      # exist upstream in MELPA keep their melpaBuild (and autoloads) with
      # only the src swapped; personal/unpublished ones use compileEmacsFiles.

      alert = esuper.alert.overrideAttrs (_: {
        src = githubSource "alert";
      });

      chess = compileEmacsFiles {
        name = "chess";
        src = githubSource "chess";
      };

      elisp-dev-mcp = esuper.elisp-dev-mcp.overrideAttrs (_: {
        src = githubSource "elisp-dev-mcp";
      });

      git-undo = esuper.git-undo.overrideAttrs (_: {
        src = githubSource "git-undo";
      });

      # gptel pinned to the rev formerly checked out in ~/.emacs.d/lisp/gptel,
      # overriding the stock MELPA gptel's src. This MUST stay a melpaBuild
      # (src override, not compileEmacsFiles) so it keeps package.el version
      # metadata: gptel-fn-complete and other gptel-* packages declare a versioned
      # dependency `(gptel "0.9.8")`, which a compileEmacsFiles package (no
      # version) cannot satisfy. The rev's Package-Requires is only transient +
      # compat, so the stock propagatedBuildInputs already suffice.
      gptel = esuper.gptel.overrideAttrs (_: {
        src = githubSource "gptel";
      });

      ledger-mode = esuper.ledger-mode.overrideAttrs (_: {
        src = githubSource "ledger-mode";
      });

      mcp-server-lib = esuper.mcp-server-lib.overrideAttrs (_: {
        src = githubSource "mcp-server-lib";
      });

      org-autolist = esuper.org-autolist.overrideAttrs (_: {
        src = githubSource "org-autolist";
      });

      vulpea = compileEmacsFiles {
        name = "vulpea";
        src = githubSource "vulpea";
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
        src = githubSource "claude-code-ide";
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
        src = githubSource "copy-code";
      };

      gptel-emacs-tools = compileEmacsFiles {
        name = "gptel-emacs-tools";
        src = githubSource "gptel-emacs-tools";
        buildInputs = with eself; [
          gptel
          transient
          compat
        ];
      };

      gptel-prompts = compileEmacsFiles {
        name = "gptel-prompts";
        src = githubSource "gptel-prompts";
        buildInputs = with eself; [
          gptel
          transient
          compat
        ];
      };

      gptel-rag = compileEmacsFiles {
        name = "gptel-rag";
        src = githubSource "gptel-rag";
        buildInputs = with eself; [
          gptel
          transient
          compat
        ];
      };

      hash-store = compileEmacsFiles {
        name = "hash-store";
        src = githubSource "hash-store";
      };

      haskell-config = compileEmacsFiles {
        name = "haskell-config";
        src = githubSource "haskell-config";
        buildInputs = with eself; [
          proof-general
        ];
      };

      initsplit = compileEmacsFiles {
        name = "initsplit";
        src = githubSource "initsplit";
      };

      llm-tool-collection = compileEmacsFiles {
        name = "llm-tool-collection";
        src = githubSource "llm-tool-collection";
      };

      loeb = compileEmacsFiles {
        name = "loeb";
        src = githubSource "loeb";
      };

      lzw = compileEmacsFiles {
        name = "lzw";
        src = githubSource "lzw";
      };

      machines =
        (compileEmacsFiles {
          name = "machines";
          src = githubSource "machines";
          # m-gptel.el requires the removed gptel-curl feature; ship that optional
          # integration as source without compiling it.
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
        src = githubSource "magit-ai";
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
        src = githubSource "ob-gptel";
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
        src = githubSource "org-agenda-overlay";
      };

      org-context = compileEmacsFiles {
        name = "org-context";
        src = githubSource "org-context";
      };

      org-devonthink = compileEmacsFiles {
        name = "org-devonthink";
        src = githubSource "org-devonthink";
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
        src = githubSource "org-drafts";
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
        src = githubSource "org-hash";
      };

      org-table-loeb = compileEmacsFiles {
        name = "org-table-loeb";
        src = githubSource "org-table-loeb";
        preBuild = ''
          rm -f test-*.el *-test*.el
        '';
      };

      org-wiki = compileEmacsFiles {
        name = "org-wiki";
        src = githubSource "org-wiki";
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
        src = githubSource "pending";
        buildInputs = with eself; [
          aio
        ];
      };

      pl = compileEmacsFiles {
        name = "pl";
        src = githubSource "pl";
      };

      springboard = compileEmacsFiles {
        name = "springboard";
        src = githubSource "springboard";
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
        src = githubSource "stock-quote";
      };

      vulpea-field = compileEmacsFiles {
        name = "vulpea-field";
        src = githubSource "vulpea-field";
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
        src = githubSource "wombag";
        buildInputs = with eself; [
          compat
          emacsql
          request
        ];
      };

      z3 = compileEmacsFiles {
        name = "z3";
        src = githubSource "z3";
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
// prev.lib.optionalAttrs (emacsSrc != null) {

  ##########################################################################

  emacsHEAD =
    with prev;
    let
      versionLine =
        lib.findFirst (line: lib.hasPrefix "AC_INIT([GNU Emacs], [" line)
          (throw "emacs-src configure.ac has no GNU Emacs version")
          (lib.splitString "\n" (builtins.readFile "${emacsSrc}/configure.ac"));
      emacsHeadVersion = lib.head (
        lib.splitString "]" (lib.removePrefix "AC_INIT([GNU Emacs], [" versionLine)
      );
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
        version = emacsHeadVersion;
        env = {
          NATIVE_FULL_AOT = "1";
          LIBRARY_PATH = lib.concatStringsSep ":" libGccJitLibraryPaths;
        };
        src = emacsSrc;
        patches = [
          (builtins.path {
            name = "inhibit-lexical-cookie-warning-67916.patch";
            path = ./emacs/patches/inhibit-lexical-cookie-warning-67916-30.patch;
          })
        ];
        preConfigure = ''
          substituteInPlace configure.ac \
            --replace-fail 'headerpad_extra=1000' 'headerpad_extra=2000'
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
