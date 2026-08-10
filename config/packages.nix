{
  hostname,
  inputs,
  pkgs,
  isClientMachine ? true,
  ...
}:
with pkgs;
let
  # packages.nix is NOT a module -- it is `import`ed as a plain function and
  # two of its three call sites (flake.nix and the downstream-consumer test
  # fixture) pass it neither `config` nor `lib`. So it reads capabilities from
  # the PURE registry rather than from `config.johnw.host`.
  registry = import ./hosts/registry.nix;
  caps = registry.capabilitiesFor { inherit hostname; };
  inherit (stdenv)
    isDarwin
    isLinux
    ;
  sys = pkgs.stdenv.hostPlatform.system;
  sourcePython313Packages = inputs.nixpkgs.legacyPackages.${sys}.python313Packages;
  aiPackagePolicy = import ../packages/ai-package-policy.nix { inherit lib; };
  inherit (aiPackagePolicy) supportsAiperf supportsGradio6;

  # Helper to conditionally include a package that may come from an overlay.
  # Returns a singleton list if the package exists in pkgs and is available on
  # this platform, empty list otherwise -- the same semantics as the portable
  # flake's optPkg, so the home and portable selections cannot disagree.
  optPkg =
    name:
    if pkgs ? ${name} && lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.${name} then
      [ pkgs.${name} ]
    else
      [ ];
  optPkgs = names: lib.concatMap optPkg names;

  agentPackages = inputs.llm-agents.packages.${sys} or { };
  localAi = inputs.nix-config-ai or (if inputs ? git-ai then import ../flake/ai.nix inputs else null);
  # config/ai.nix hard-asserts this same input; a consumer that installs agent
  # packages without the portable flake must fail loudly rather than silently
  # receive unwrapped upstream binaries.
  patchAgentPackage =
    if localAi == null then
      _name: _package:
      throw "config/packages.nix requires inputs.nix-config-ai (or the in-repo flake/ai.nix route) to wrap managed agent packages"
    else
      localAi.lib.patchAgentPackage pkgs;
  optAgent =
    name: if agentPackages ? ${name} then [ (patchAgentPackage name agentPackages.${name}) ] else [ ];

  # Only these source-project inputs are user applications. Adding a flake
  # input must never change a profile unless its name is added here. Missing
  # inputs remain valid for downstream flakes with reduced input sets.
  userPackageInputAllowlist = [
    "gh-to-org"
    "git-all"
    "obr"
    "org2jsonl"
    "rag-client"
    "rust-overlay"
    "sizes"
    "una"
  ]
  ++ lib.optionals isDarwin [
    "gitlib"
    "hours"
    "org-jw"
    "pushme"
    "renamer"
    "trade-journal"
  ];
  userPackageInputNames = lib.sort builtins.lessThan (
    lib.filter (
      name: inputs ? ${name} && inputs.${name} ? packages.${sys}.default
    ) userPackageInputAllowlist
  );
  userPackageInputs = map (name: inputs.${name}.packages.${sys}.default) userPackageInputNames;
in
rec {
  inherit userPackageInputNames;

  exe = if stdenv.targetPlatform.isx86_64 then haskell.lib.justStaticExecutables else lib.id;

  myEmacsPackages = import ./emacs.nix pkgs;

  emacs30Env =
    if pkgs ? emacs30Env then
      pkgs.emacs30Env (epkgs: (builtins.filter (x: !x.excluded or false) (myEmacsPackages epkgs)))
    else
      null;
  emacs30MacPortEnv =
    if pkgs ? emacs30MacPortEnv then
      pkgs.emacs30MacPortEnv (epkgs: (builtins.filter (x: !x.excluded or false) (myEmacsPackages epkgs)))
    else
      null;
  emacsHEADEnv = if pkgs ? emacsHEADEnv then pkgs.emacsHEADEnv myEmacsPackages else null;

  package-list =

    # ── Emacs (Darwin workstation clients only) ──────────────────────
    lib.optionals (isClientMachine && caps.isDarwinWorkstation) (
      lib.optional (emacs30MacPortEnv != null) emacs30MacPortEnv
      ++ [
        eask-cli
        emacs-lsp-booster
      ]
    )

    # ── Haskell Tools ────────────────────────────────────────────────
    ++ [
      (exe haskellPackages.hasktags)
      (exe haskellPackages.hpack)
      (lib.hiPrio (exe haskellPackages.ormolu))
      (exe haskellPackages.pointfree)
    ]

    # ── Explicit user applications from source-project inputs ───────
    ++ userPackageInputs

    # ── Shell & Terminal Utilities ───────────────────────────────────
    ++ [
      bashInteractive
      bash-completion
      bat
      eternal-terminal
      eza
      fzf
      nnn
      rlwrap
      screen
      sdcv
      shellcheck
      shfmt
      tealdeer
      tmux
      tree
      w3m
      watch
      yazi
      zsh
      zsh-syntax-highlighting
    ]

    # ── Core System Utilities ────────────────────────────────────────
    ++ [
      cacert
      coreutils
      diffstat
      diffutils
      entr
      findutils
      fontconfig
      fswatch
      gawk
      getopt
      gnugrep
      gnumake
      gnused
      gnutar
      pkgs.hostname
      less
      libxml2
      libxslt
      loccount
      m4
      more
      ntp
      p7zip
      parallel
      patch
      patchutils
      pcre
      (perl.withPackages (perl-pkgs: with perl-pkgs; [ ImageExifTool ]))
      renameutils
      ripgrep
      scc
      time
      translate-shell
      (lib.lowPrio ctags)
      universal-ctags
      tree-sitter
      unixtools.ifconfig
      unixtools.netstat
      unixtools.ping
      unixtools.route
      unixtools.top
      watchman
      xapian
      xauth
      xhost
    ]

    # ── Networking Tools ─────────────────────────────────────────────
    ++ [
      aria2
      autossh
      curl
      dstp
      fping
      httpie
      httrack
      iftop
      iperf3
      lftp
      mitmproxy
      mosh
      mtr
      nmap
      openssh
      openvpn
      sift
      socat
      spiped
      wget
      wireguard-tools
    ]

    # ── DNS Tools ────────────────────────────────────────────────────
    ++ [
      dnstracer
      dnsutils
      pdnsd
      sipcalc
    ]

    # ── Git Tools ────────────────────────────────────────────────────
    ++ [
      delta
      gh
      gist
      (exe git-annex)
      git-annex-remote-rclone
      git-absorb
      git-autofixup
      git-branchstack
      git-cliff
    ]
    ++ lib.optionals caps.isDarwinWorkstation [ git-crypt ]
    ++ [
      git-delete-merged-branches
      (lib.lowPrio git-fame)
      git-filter-repo
      git-gone
      git-hub
      git-imerge
      git-lfs
      git-machete
      mergiraf
      git-my
      git-octopus
      graphite-cli
      git-quick-stats
      git-quickfix
      git-recent
      git-reparent
      git-repo
    ]
    ++ lib.optionals caps.isDarwinWorkstation [ git-secret ]
    ++ [
      git-series
      git-sizer
      (lib.hiPrio git-standup)
      git-subrepo
      git-vendor
      git-when-merged
      git-workspace
      gitRepo
      gitflow
      gitls
      gitstats
      hub
      tig
      top-git
      subversion
      tea
    ]
    ++ lib.optional (pkgs ? git-pr) (lib.hiPrio pkgs.git-pr)
    ++ lib.optional (pkgs ? git-scripts) (lib.lowPrio pkgs.git-scripts)

    # ── Nix Tools ────────────────────────────────────────────────────
    ++ [
      cachix
      deadnix
      devenv
      direnv
      nix-diff
      nix-index
      nix-info
      nix-prefetch-git
      nix-tree
      nixpkgs-fmt
      nixfmt
      statix
    ]

    # ── Programming Languages & Dev Tools ────────────────────────────
    ++ [
      act
      # Agda and agda2-mode derive from the same haskellPackages.Agda.
      (agda.withPackages (
        agda-pkgs: with agda-pkgs; [
          agda-categories
          standard-library
        ]
      ))
      cmake
      cmdperf
      doxygen
      go-jira
      bun
      graphviz-nox
      hurl
      igrep
      jdk
      just
      jupyter
      lefthook
      nodejs_22
      pkg-config
      pnpm
      (lib.hiPrio (
        python3.withPackages (
          python-pkgs:
          with python-pkgs;
          [
            autoflake
            basedpyright
            black # Python code formatter
            ruff # Python code linter/formatter
            flake8 # Python code linter
            hf-xet
            huggingface-hub
            isort # Python code formatter
            numpy
            pandas
            pylint
            requests
            stdenv
            venvShellHook
          ]
          ++ lib.optional (isDarwin && python-pkgs ? mlx-speech) python-pkgs.mlx-speech
        )
      ))
      pyright # LSP server for Python
      protobufc
      ruby
      scc
      sccache
      tlaplus
      uv
      wabt
      z3
    ]
    ++ optPkg "yamale"
    ++ [
      yuicompressor
    ]

    # ── Text Processing & Documents ──────────────────────────────────
    ++ [
      asciidoctor
      aspell
      aspellDicts.en
      ditaa
      dot2tex
      figlet
      gnuplot
      groff
      highlight
      html-tidy
      inkscape.out
      khal
      librsvg
      mdformat
      pandoc
      pdfgrep
      plantuml
      poppler-utils
      qpdf
      sourceHighlight
      svg2tikz
    ]
    ++ optPkg "filetags"
    ++ optPkg "org2tc"

    # ── Data & JSON/YAML Tools ───────────────────────────────────────
    ++ [
      cbor-diag
      csvkit
      fx
      jo
      jiq
      jq
      jqp
      json2yaml
      metabase
      (postgresql.withPackages (postgres-pkgs: with postgres-pkgs; [ pgvector ]))
      libpq
      sqlite
      sqlite-analyzer
      sqldiff
      yq
    ]
    ++ optPkg "tsvutils"

    # ── File Management Tools ────────────────────────────────────────
    ++ [
      dust
      fd
      fdupes
      fpart
      httm
      lzip
      lzop
      rclone
      restic
      rmtrash
      rsync
      squashfsTools
      srm
      stow
      trash-cli
      unrar
      unzip
      xz
      zfs-prune-snapshots
      zip
    ]

    # ── Media Tools ──────────────────────────────────────────────────
    ++ [
      exiv2
      eyed3
      ffmpeg
      imagemagickBig
      imgcat
      kew
      qrencode
      vega-lite
      yt-dlp
      zbar
    ]

    # ── Security & Crypto ────────────────────────────────────────────
    ++ [
      apg
      b3sum
      mkcert
      nss
      opensc
      openssl
    ]
    ++ lib.optionals caps.isDarwinWorkstation [
      paperkey
      pass-git-helper
    ]
    ++ [
      sshfs
    ]
    ++ optPkg "sshify"

    # ── Monitoring & System Info ─────────────────────────────────────
    ++ [
      bandwhich
      bottom
      btop
      ctop
      htop
      killall
      lnav
      lsof
      multitail
      procps
      psrecord
      pstree
      pv
      smartmontools
    ]

    # ── Email Tools ──────────────────────────────────────────────────
    ++ [
      imapfilter
      isync
      mb2md
      procmail
    ]
    ++ optPkg "sieveshell"

    # ── Cloud & Containers ───────────────────────────────────────────
    ++ [
      awscli2
      backblaze-b2
      google-cloud-sdk
      kubectl
      qemu
      libvirt
      samba
      slackdump
    ]

    # ── AI & LLM Tools ──────────────────────────────────────────────
    ++ [
      (lib.hiPrio llama-cpp)
      openmpi
      qdrant
    ]
    ++ lib.optionals (supportsAiperf sourcePython313Packages) (optPkg "aiperf")
    ++ optPkgs (aiPackagePolicy.groups.common ++ aiPackagePolicy.groups.homeOnly)
    ++ optAgent "claude-code"
    ++ optAgent "ccusage"
    ++ optAgent "ccstatusline"
    ++ optAgent "codex"
    ++ optAgent "droid"
    ++ optAgent "git-surgeon"
    ++ optAgent "opencode"
    ++ optPkg "unisessions"

    # ── MCP Servers & Agent Tools ────────────────────────────────────
    # drafts-mcp-server is macOS-only (drives Drafts.app via AppleScript)
    ++ lib.optionals isDarwin (optPkg "drafts-mcp-server")
    ++ (
      if pkgs ? mcp-server-sequential-thinking then
        [ (lib.hiPrio pkgs.mcp-server-sequential-thinking) ]
      else
        [ ]
    )

    # ── User Scripts & Custom Packages ───────────────────────────────
    ++ (if pkgs ? my-scripts then [ (lib.lowPrio pkgs.my-scripts) ] else [ ])
    ++ optPkg "nix-scripts"
    ++ optPkg "dirscan"
    ++ optPkg "hammer"
    ++ optPkg "hashdb"
    ++ optPkg "ledger_HEAD"
    ++ optPkg "linkdups"
    ++ optPkg "lipotell"
    ++ optPkg "markless"
    ++ optPkg "gogcli"

    # ── Miscellaneous ────────────────────────────────────────────────
    ++ [
      global
      mcat
      siege
      taskjuggler
    ]

    # ── Darwin-Only Packages ─────────────────────────────────────────
    ++ lib.optionals isDarwin [
      contacts
      darwin.cctools
      m-cli
      macmon
    ]
    ++ lib.optionals caps.isDarwinWorkstation [ pinentry_mac ]
    ++ lib.optionals isDarwin [
      pngpaste
      terminal-notifier
      xquartz
    ]
    ++ lib.optionals (isDarwin && supportsGradio6 sourcePython313Packages) (optPkg "vllm-mlx")
    ++ lib.optionals isDarwin (optPkg "mtplx")
    ++ lib.optionals isDarwin (optPkg "omlx")

    # ── Linux-Only Packages ──────────────────────────────────────────
    ++ lib.optionals isLinux [
      ratpoison
    ]

    # ── Host-Specific Packages (hera) ────────────────────────────────
    ++ lib.optionals caps.isHera (
      [
        himalaya
        openai-whisper
        openhue-cli
        soco-cli
        spotify-player
      ]
      ++ optAgent "mcporter"
    );
}
