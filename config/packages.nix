{
  hostname,
  inputs,
  pkgs,
  isClientMachine ? true,
  ...
}:
with pkgs;
let
  inherit (stdenv)
    isDarwin
    isLinux
    ;
  sys = pkgs.stdenv.hostPlatform.system;

  # Helper to conditionally include a package that may come from an overlay.
  # Returns a singleton list if the package exists in pkgs, empty list otherwise.
  optPkg = name: if pkgs ? ${name} then [ pkgs.${name} ] else [ ];

  agentPackages = inputs.llm-agents.packages.${sys} or { };
  patchAgentPackage =
    if inputs ? ai-nix && inputs.ai-nix ? lib && inputs.ai-nix.lib ? patchAgentPackage then
      inputs.ai-nix.lib.patchAgentPackage pkgs
    else
      _name: package: package;
  optAgent =
    name: if agentPackages ? ${name} then [ (patchAgentPackage name agentPackages.${name}) ] else [ ];

  # Flake inputs whose default package should NOT be auto-installed.
  # The first group is consumed through tooling, overlays, modules, or
  # explicit handling below. On Linux, the conditional group also excludes
  # tools that are intentionally installed only on Darwin.
  nonUserPackageInputs = [
    "darwin" # nix-darwin tooling
    "home-manager" # home-manager tooling
    "ai-nix" # consumed via overlay
    "llm-agents" # multi-package; specific packages chosen below
    "dirscan" # consumed via 30-data-tools overlay
    "git-ai" # consumed via overlay / home-manager module
    "hakyll" # local dev source only, not installed
  ]
  ++ lib.optionals isLinux [
    "gitlib" # its default package is git-monitor
    "hours"
    "org-jw"
    "pushme"
    "renamer"
    "trade-journal"
  ];

  # Auto-install every flake input that exposes packages.${sys}.default
  # and isn't in the block-list above. Tolerates hosts (e.g. NixOS) that
  # import this file with a smaller set of inputs.
  userPackageInputs = lib.filterAttrs (
    name: v: !(lib.elem name nonUserPackageInputs) && v ? packages.${sys}.default
  ) inputs;
in
rec {
  userPackageInputNames = builtins.attrNames userPackageInputs;

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

    # ── Emacs (client machines only) ────────────────────────────────
    lib.optionals isClientMachine (
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

    # ── Custom Flake Inputs (auto-discovered) ────────────────────────
    ++ lib.mapAttrsToList (_: v: v.packages.${sys}.default) userPackageInputs

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
      git-crypt
      git-delete-merged-branches
      # (lib.lowPrio git-extras)
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
      git-secret
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
      # Agda with registered libraries. Version-aligned with agda2-mode
      # (config/emacs.nix) by construction: both derive from the same
      # haskellPackages.Agda. That Agda depends on top-level pkgs.emacs,
      # which overlays/10-emacs.nix maps to emacs30-macport on Darwin
      # (emacs30 on Linux), so Agda and its library set build locally
      # instead of substituting, and rebuild when this overlay's emacs
      # changes.
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
      # sbcl  # Disabled: ECL bootstrap broken on Darwin/Apple Silicon
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
      # recoll-nox
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
      paperkey
      pass-git-helper
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
    ++ optPkg "plasma-wiki"
    ++ optPkg "plasma-fractal"
    ++ optPkg "aiperf"
    ++ optPkg "guidellm"
    ++ optPkg "llama-swap"
    ++ optPkg "lazycodex-ai"
    ++ optPkg "gguf-tools"
    ++ optPkg "qdrant-web-ui"
    ++ optPkg "agent-deck"
    ++ optPkg "agnix"
    ++ optPkg "claude-vault"
    ++ optPkg "claude-replay"
    ++ optAgent "claude-code"
    ++ optAgent "ccusage"
    ++ optAgent "ccstatusline"
    ++ optAgent "codex"
    ++ optAgent "droid"
    ++ optAgent "git-surgeon"
    ++ optAgent "opencode"
    ++ optAgent "pi"
    # ++ optAgent "gemini-cli"

    # ── MCP Servers & Agent Tools ────────────────────────────────────
    ++ optPkg "sherlock-db"
    ++ optPkg "pal-mcp-server"
    ++ optPkg "rustdocs-mcp-server"
    ++ optPkg "context-hub"
    ++ optPkg "context7-mcp"
    ++ optPkg "playwright-mcp"
    ++ optPkg "github-mcp-server"
    ++ optPkg "stock-trader-mcp"
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
      mcat
      taskjuggler
    ]

    # ── Darwin-Only Packages ─────────────────────────────────────────
    ++ lib.optionals isDarwin [
      contacts
      darwin.cctools
      global # Broken on Linux (embedded libdb incompatible with gcc strict typing)
      m-cli
      macmon
      pinentry_mac
      pngpaste
      siege # Broken on Linux (glibc 2.42 strcasecmp conflict)
      terminal-notifier
      xquartz
    ]
    ++ lib.optionals isDarwin (optPkg "vllm-mlx")
    ++ lib.optionals isDarwin (optPkg "mtplx")
    ++ lib.optionals isDarwin (optPkg "omlx")

    # ── Linux-Only Packages ──────────────────────────────────────────
    ++ lib.optionals isLinux [
      ratpoison # X11 WM; not usable on Darwin
    ]
    # ++ lib.optionals isLinux (optPkg "cpx")

    # ── Host-Specific Packages (hera) ────────────────────────────────
    ++ lib.optionals (hostname == "hera") (
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
