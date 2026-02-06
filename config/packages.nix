{
  system,
  hostname,
  inputs,
  pkgs,
  ...
}:
with pkgs;
rec {
  exe = if stdenv.targetPlatform.isx86_64 then haskell.lib.justStaticExecutables else lib.id;

  myEmacsPackages = import ./emacs.nix pkgs;

  emacs30Env = pkgs.emacs30Env (
    epkgs: (builtins.filter (x: !x.excluded or false) (myEmacsPackages epkgs))
  );
  emacs30MacPortEnv = pkgs.emacs30MacPortEnv (
    epkgs: (builtins.filter (x: !x.excluded or false) (myEmacsPackages epkgs))
  );
  emacsHEADEnv = pkgs.emacsHEADEnv myEmacsPackages;

  rag-client = inputs.rag-client.packages.${system}.default;

  package-list = [
    (exe haskellPackages.hasktags)
    (exe haskellPackages.hpack)
    (lib.hiPrio (exe haskellPackages.ormolu))
    (exe haskellPackages.pointfree)
    inputs.git-all.packages.${system}.default
    inputs.gitlib.packages.${system}.default
    inputs.hours.packages.${system}.default
    inputs.org-jw.packages.${system}.default
    inputs.pushme.packages.${system}.default
    inputs.renamer.packages.${system}.default
    inputs.sizes.packages.${system}.default
    inputs.trade-journal.packages.${system}.default
    inputs.una.packages.${system}.default
    inputs.gh-to-org.packages.${system}.default
    act
    apg
    aria2
    asciidoctor
    aspell
    aspellDicts.en
    autossh
    awscli2
    b3sum
    backblaze-b2
    bandwhich
    bash-completion
    bashInteractive
    bat
    btop
    cacert
    cargo-cache
    cbor-diag
    cmake
    contacts
    coreutils
    csvkit
    ctop
    curl
    darwin.cctools
    diffstat
    diffutils
    direnv
    devenv
    dirscan
    ditaa
    dnstracer
    dnsutils
    dot2tex
    doxygen
    dstp
    dust
    eask-cli
    # emacs30Env
    emacs30MacPortEnv
    # emacsHEADEnv
    emacs-lsp-booster
    entr
    exiv2
    eyed3
    eza
    fd
    fdupes
    ffmpeg
    figlet
    filetags
    findutils
    fontconfig
    fpart
    fping
    fswatch
    fx
    fzf
    gawk
    getopt
    delta
    gh
    gist
    git-absorb
    git-autofixup
    git-branchless
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
    git-my
    git-octopus
    (lib.hiPrio git-pr)
    git-quick-stats
    git-quickfix
    git-recent
    git-reparent
    git-repo
    (lib.lowPrio git-scripts)
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
    global
    gnugrep
    gnumake
    gnuplot
    gnused
    gnutar
    go-jira
    google-cloud-sdk
    graphviz-nox
    groff
    hammer
    hashdb
    highlight
    pkgs.hostname
    html-tidy
    htop
    httm
    httpie
    httrack
    iftop
    igrep
    imagemagickBig
    imapfilter
    imgcat
    inkscape.out
    iperf3
    isync
    jdk
    jiq
    jo
    jq
    jqp
    json2yaml
    jupyter
    just
    khard
    killall
    kubectl
    ledger_HEAD
    less
    lftp
    librsvg
    libxml2
    libxslt
    linkdups
    lipotell
    lnav
    loccount
    lsof
    lzip
    lzop
    m-cli
    m4
    macmon
    mb2md
    mcat
    metabase
    mitmproxy
    mkcert
    more
    mtr
    multitail
    my-scripts
    nix-diff
    nix-index
    nix-info
    nix-prefetch-git
    nix-scripts
    nix-tree
    nixpkgs-fmt
    nixfmt
    nmap
    nodejs_22
    nss
    ntp
    opensc
    openssh
    openssl
    openvpn
    org2tc
    p7zip
    pandoc
    paperkey
    parallel
    pass-git-helper
    patch
    patchutils
    pcre
    pdnsd
    pdfgrep
    (perl.withPackages (perl-pkgs: with perl-pkgs; [ ImageExifTool ]))
    pinentry_mac
    pkg-config
    plantuml
    pngpaste
    pnpm
    poppler-utils
    (postgresql.withPackages (postgres-pkgs: with postgres-pkgs; [ pgvector ]))
    libpq
    procmail
    procps
    protobufc
    psrecord
    pstree
    pv
    (lib.hiPrio (
      python3.withPackages (
        python-pkgs: with python-pkgs; [
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
      )
    ))
    pyright # LSP server for Python
    qdrant
    qemu
    libvirt
    qpdf
    qrencode
    rag-client
    ratpoison
    rclone
    # recoll-nox
    renameutils
    restic
    ripgrep
    rlwrap
    rmtrash
    rsync
    ruby
    samba
    # sbcl  # Disabled: ECL bootstrap broken on Darwin/Apple Silicon
    scc
    sccache
    screen
    sdcv
    shfmt
    siege
    sieveshell
    sift
    sipcalc
    slackdump
    smartmontools
    socat
    sourceHighlight
    spiped
    sqlite
    sqlite-analyzer
    sqldiff
    squashfsTools
    srm
    sshfs
    sshify
    stow
    subversion
    svg2tikz
    taskjuggler
    terminal-notifier
    time
    tlaplus
    tmux
    translate-shell
    travis
    tree
    tree-sitter
    tsvutils
    (lib.lowPrio ctags)
    universal-ctags
    unixtools.ifconfig
    unixtools.netstat
    unixtools.ping
    unixtools.route
    unixtools.top
    unrar
    unzip
    uv
    w3m
    wabt
    watch
    watchman
    wget
    wireguard-tools
    xapian
    xorg.xauth
    xorg.xhost
    xquartz
    xz
    yamale
    yq
    yuicompressor
    z
    z3
    zbar
    zfs-prune-snapshots
    zip
    zsh
    zsh-syntax-highlighting

    aider-chat
    (lib.hiPrio llama-cpp)
    llama-swap
    gguf-tools
    openmpi
    qdrant
    qdrant-web-ui
    rustdocs-mcp-server

    context7-mcp
    playwright-mcp
    github-mcp-server
    (lib.hiPrio mcp-server-sequential-thinking)

    (exe git-annex)
    git-annex-remote-rclone
  ]
  # Linux-only packages (not available on Darwin/macOS)
  ++ lib.optionals stdenv.isLinux [
    cpx # Modern, fast file copy tool with progress bars and resume support
  ]
  ++ (with inputs.llm-agents.packages.${system}; [
    droid
    claude-code
    # claude-code-acp
    ccusage
    kilocode-cli
    opencode
    # gemini-cli
    # codex
    ollama
    openclaw
  ]);
}
