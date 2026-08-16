{
  inputs,
  pkgs,
}:

let
  inherit (pkgs) lib;
  toolSources = import ./source-catalog.nix "tools";
  gitAll = pkgs.haskellPackages.git-all;

  haskellExecutable =
    name:
    pkgs.haskell.lib.justStaticExecutables (
      pkgs.haskellPackages.callCabal2nix name inputs.${name}.outPath { }
    );
  profiledHaskellExecutable =
    name:
    pkgs.haskell.lib.enableExecutableProfiling (
      pkgs.haskellPackages.callCabal2nix name inputs.${name}.outPath { }
    );
  gitlibSource = inputs.gitlib.outPath;
  hlibgit2Source = pkgs.runCommand "hlibgit2-src" { } ''
    cp -r ${gitlibSource}/hlibgit2 $out
    chmod -R u+w $out
    rm -rf $out/libgit2
    cp -r ${inputs.libgit2-src.outPath} $out/libgit2
  '';
  gitlibHaskellPackages = pkgs.haskellPackages.extend (
    final: _previous: {
      gitlib = final.callCabal2nix "gitlib" (gitlibSource + "/gitlib") { };
      hlibgit2 = pkgs.haskell.lib.addExtraLibraries (final.callCabal2nix "hlibgit2" hlibgit2Source {
        inherit (pkgs) git;
      }) [ pkgs.openssl ];
      gitlib-test = final.callCabal2nix "gitlib-test" (gitlibSource + "/gitlib-test") { };
      gitlib-libgit2 = final.callCabal2nix "gitlib-libgit2" (gitlibSource + "/gitlib-libgit2") { };
      git-monitor = final.callCabal2nix "git-monitor" (gitlibSource + "/git-monitor") { };
    }
  );
  timeRecurrence =
    pkgs.haskell.lib.overrideCabal
      (pkgs.haskell.lib.doJailbreak (pkgs.haskell.lib.unmarkBroken pkgs.haskellPackages.time-recurrence))
      (old: {
        # time-recurrence predates the calendarYear/calendarMonth accessors that
        # Data.Time now exports. Keep its own record fields unambiguous.
        postPatch = (old.postPatch or "") + ''
          sed -i '/^import Data.Time$/c\import Data.Time hiding (calendarDay, calendarMonth, calendarYear)' \
            src/Data/Time/CalendarTime/CalendarTime.hs
          sed -i '/^> import Data.Time$/c\> import Data.Time hiding (Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday, January, February, March, April, May, June, July, August, September, October, November, December)' \
            tests/Tests.lhs
        '';
      });
  hours = pkgs.haskell.lib.justStaticExecutables (
    pkgs.haskellPackages.callCabal2nix "hours" inputs.hours.outPath {
      time-recurrence = timeRecurrence;
    }
  );
  orgJwSource = inputs.org-jw.outPath;
  orgJwPackageNames = [
    "flatparse-util"
    "org-cbor"
    "org-data"
    "org-db"
    "org-dot"
    "org-filetags"
    "org-json"
    "org-jw"
    "org-lint"
    "org-parse"
    "org-print"
    "org-site"
    "org-types"
  ];
  orgJwHakyllSource =
    assert toolSources.hakyll-jw.source.fetcher == "fetchFromGitHub";
    pkgs.fetchFromGitHub toolSources.hakyll-jw.source.args;
  orgJwHaskellPackages = pkgs.haskellPackages.extend (
    final: _previous:
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = final.callCabal2nix name (orgJwSource + "/${name}") { };
      }) orgJwPackageNames
    )
    // {
      hakyll = final.callCabal2nix "hakyll" orgJwHakyllSource { };
      org-lint =
        pkgs.haskell.lib.overrideCabal (final.callCabal2nix "org-lint" (orgJwSource + "/org-lint") { })
          (old: {
            # Link-check tests spawn curl to exercise the URL probe paths.
            testToolDepends = (old.testToolDepends or [ ]) ++ [ pkgs.curl ];
          });
      org-site =
        pkgs.haskell.lib.overrideCabal (final.callCabal2nix "org-site" (orgJwSource + "/org-site") { })
          (old: {
            # The two Pandoc API branches in this source revision are reversed.
            postPatch = (old.postPatch or "") + ''
              substituteInPlace src/Org/Site.hs \
                --replace-fail '#if MIN_VERSION_pandoc(3,7,0)' \
                  '#if !MIN_VERSION_pandoc(3,7,0)'
            '';
          });
    }
  );
  orgJw = pkgs.haskell.lib.justStaticExecutables (
    pkgs.haskell.lib.overrideCabal orgJwHaskellPackages.org-jw (old: {
      buildTools = (old.buildTools or [ ]) ++ [ pkgs.removeReferencesTo ];
      # Cabal's Paths_* modules embed unused library, executable, and config
      # directories. Those library outputs retain GHC, while Hakyll's separate
      # data output (which is usable at runtime) remains referenced.
      postFixup = (old.postFixup or "") + ''
        remove-references-to \
          -t ${orgJwHaskellPackages.hakyll} \
          -t ${orgJwHaskellPackages.pandoc-types} \
          -t ${orgJwHaskellPackages.typst} \
          "$out/bin/org"
      '';
    })
  );
  sizes = pkgs.haskell.lib.justStaticExecutables (
    pkgs.haskell.lib.overrideCabal (pkgs.haskellPackages.callCabal2nix "sizes" inputs.sizes.outPath { })
      (old: {
        # Cabal does not put a package's executable on PATH for its test suite.
        # Three CLI integration tests invoke `sizes` by name.
        preCheck = (old.preCheck or "") + ''
          export PATH="$PWD/dist/build/sizes:$PATH"
        '';
      })
  );

  ghToOrgPython = pkgs.python3.override {
    packageOverrides = _final: previous: {
      typer = previous.typer.overridePythonAttrs (_old: {
        doCheck = false;
      });
    };
  };
  ghToOrgRuntimeDependencies = pythonPackages: [
    pythonPackages.pydantic
    pythonPackages.typer
    pythonPackages.rich
    pythonPackages.httpx
  ];

  ragClientPython = pkgs.python3.withPackages (
    pythonPackages: with pythonPackages; [
      pip
      setuptools
      wheel
      virtualenv
    ]
  );
  ragClientLibraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    glib
    libpq
    openssl
    pkg-config
  ];
  ragClientLibraryPath = lib.makeLibraryPath ragClientLibraries;
in
{
  # These applications only need their source trees. Building them from the
  # already-open host package set avoids evaluating one complete flake (and,
  # for Haskell projects, one HaskellNix universe) per installed executable.
  gh-to-org = ghToOrgPython.pkgs.buildPythonApplication {
    pname = "gh-org-sync";
    version = "1.0.0";
    pyproject = true;
    src = lib.cleanSource inputs.gh-to-org.outPath;

    build-system = [ ghToOrgPython.pkgs.hatchling ];
    dependencies = ghToOrgRuntimeDependencies ghToOrgPython.pkgs;
    nativeBuildInputs = [ pkgs.makeWrapper ];

    postInstall = ''
      wrapProgram $out/bin/gh-org-sync \
        --prefix PATH : ${lib.makeBinPath [ pkgs.gh ]}
    '';
    doCheck = false;

    meta = {
      description = "Sync GitHub issues to Org-mode files with bidirectional awareness";
      license = lib.licenses.bsd3;
      mainProgram = "gh-org-sync";
    };
  };

  git-all =
    assert gitAll.version == "1.8.1";
    pkgs.haskell.lib.justStaticExecutables (
      pkgs.haskell.lib.overrideSrc gitAll {
        src = inputs.git-all.outPath;
      }
    );

  gitlib = pkgs.haskell.lib.justStaticExecutables gitlibHaskellPackages.git-monitor;

  inherit hours;

  org2jsonl = pkgs.rustPlatform.buildRustPackage {
    pname = "org2jsonl";
    version = "0.1.0";
    src = inputs.org2jsonl.outPath;
    cargoLock.lockFile = inputs.org2jsonl.outPath + "/Cargo.lock";
    strictDeps = true;
    buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      pkgs.libiconv
      pkgs.apple-sdk_15
    ];
  };

  org-jw = orgJw;

  pushme = profiledHaskellExecutable "pushme";
  renamer = profiledHaskellExecutable "renamer";
  trade-journal = profiledHaskellExecutable "trade-journal";

  una = haskellExecutable "una";

  # Apply rust-overlay to the package set already used by the host. This is the
  # same toolchain derivation as the input's default package without importing
  # another nixpkgs for each system.
  rust-overlay = (pkgs.extend (import inputs.rust-overlay.outPath)).rust-bin.stable.latest.default;

  inherit sizes;

  rag-client = pkgs.stdenv.mkDerivation {
    pname = "rag-client";
    version = "1.0.0";
    src = inputs.rag-client.outPath;

    nativeBuildInputs = [
      pkgs.makeWrapper
      ragClientPython
    ];
    buildInputs = ragClientLibraries ++ [ pkgs.libpq.pg_config ];

    dontBuild = true;
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/share/lib/rag-client
      cp -p *.py requirements.txt $out/share/lib/rag-client

      makeWrapper ${pkgs.uv}/bin/uv $out/bin/rag-client \
        --set LD_LIBRARY_PATH "${ragClientLibraryPath}" \
        --set DYLD_LIBRARY_PATH "${ragClientLibraryPath}" \
        --set PATH "${pkgs.libpq.pg_config}/bin:${pkgs.cmake}/bin:${pkgs.pkg-config}/bin:${pkgs.git}/bin:$PATH" \
        --set NIX_SSL_CERT_FILE "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" \
        --set SSL_CERT_FILE "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" \
        --add-flags run \
        --add-flags --no-config \
        --add-flags --with-requirements \
        --add-flags $out/share/lib/rag-client/requirements.txt \
        --add-flags $out/share/lib/rag-client/main.py

      runHook postInstall
    '';
    doCheck = false;
  };
}
