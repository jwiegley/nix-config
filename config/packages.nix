{
  hostname,
  inputs,
  pkgs,
  ...
}:
with pkgs;
let
  inherit (stdenv) isDarwin isLinux;
  sys = pkgs.stdenv.hostPlatform.system;

  # Helper to conditionally include a package from a flake input.
  # Returns a singleton list if the input exists, empty list otherwise.
  inputPkg = name: if inputs ? ${name} then [ inputs.${name}.packages.${sys}.default ] else [ ];

  # Helper to conditionally include a package that may come from an overlay.
  # Returns a singleton list if the package exists in pkgs, empty list otherwise.
  optPkg = name: if pkgs ? ${name} then [ pkgs.${name} ] else [ ];
in
rec {
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

  rag-client = if inputs ? rag-client then inputs.rag-client.packages.${sys}.default else null;

  package-list = [
    (exe haskellPackages.hasktags)
    (exe haskellPackages.hpack)
    (lib.hiPrio (exe haskellPackages.ormolu))
    (exe haskellPackages.pointfree)
  ]
  ++ inputPkg "promptdeploy"
  ++ inputPkg "git-all"
  ++ inputPkg "gitlib"
  ++ inputPkg "hours"
  ++ inputPkg "org-jw"
  ++ inputPkg "pushme"
  ++ inputPkg "renamer"
  ++ inputPkg "sizes"
  ++ inputPkg "trade-journal"
  ++ inputPkg "una"
  ++ inputPkg "gh-to-org"
  ++ inputPkg "obr"
  ++ inputPkg "org2jsonl"
  ++ [
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
    bottom
    bashInteractive
    bat
    btop
    cacert
    caligula
    cargo-cache
    cbor-diag
    cmake
  ]
  ++ lib.optionals isDarwin [
    contacts
  ]
  ++ [
    coreutils
    csvkit
    ctop
    curl
  ]
  ++ lib.optionals isDarwin [
    darwin.cctools
  ]
  ++ [
    deadnix
    diffstat
    diffutils
    direnv
    devenv
  ]
  ++ optPkg "dirscan"
  ++ [
    ditaa
    dnstracer
    dnsutils
    dot2tex
    doxygen
    dstp
    dust
    eask-cli
    # emacs30Env
  ]
  ++ lib.optional (emacs30MacPortEnv != null) emacs30MacPortEnv
  ++ [
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
  ]
  ++ optPkg "filetags"
  ++ [
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
    mergiraf
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
  ]
  ++ optPkg "gogcli"
  ++ [
    google-cloud-sdk
    graphviz-nox
    groff
  ]
  ++ optPkg "hammer"
  ++ optPkg "hashdb"
  ++ [
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
    kew
    khard
    killall
    kubectl
  ]
  ++ optPkg "ledger_HEAD"
  ++ [
    lefthook
    less
    lftp
    librsvg
    libxml2
    libxslt
  ]
  ++ optPkg "linkdups"
  ++ optPkg "lipotell"
  ++ [
    lnav
    loccount
    lsof
    lzip
    lzop
  ]
  ++ lib.optionals isDarwin [
    m-cli
    macmon
  ]
  ++ [
    m4
  ]
  ++ optPkg "mapq"
  ++ optPkg "markless"
  ++ [
    mb2md
    mcat
    metabase
    mitmproxy
    mkcert
    more
    mtr
    multitail
  ]
  ++ (if pkgs ? my-scripts then [ (lib.lowPrio pkgs.my-scripts) ] else [ ])
  ++ [
    nnn
    nix-diff
    nix-index
    nix-info
    nix-prefetch-git
  ]
  ++ optPkg "nix-scripts"
  ++ [
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
  ]
  ++ optPkg "org2tc"
  ++ [
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
  ]
  ++ lib.optionals isDarwin [
    pinentry_mac
    pngpaste
  ]
  ++ [
    pkg-config
    plantuml
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
    qemu
    libvirt
    qpdf
    qrencode
  ]
  ++ lib.optional (rag-client != null) rag-client
  ++ [
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
  ]
  ++ optPkg "sieveshell"
  ++ [
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
  ]
  ++ optPkg "sshify"
  ++ [
    statix
    stow
    subversion
    svg2tikz
    taskjuggler
    tealdeer
  ]
  ++ lib.optionals isDarwin [
    terminal-notifier
  ]
  ++ [
    time
    tlaplus
    tmux
    translate-shell
    trash-cli
    tree
    tree-sitter
  ]
  ++ optPkg "tsvutils"
  ++ [
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
    vega-lite
    w3m
    wabt
    watch
    watchman
    wget
    wireguard-tools
    xapian
    xauth
    xhost
  ]
  ++ lib.optionals isDarwin [
    xquartz
  ]
  ++ [
    xz
    yazi
  ]
  ++ optPkg "yamale"
  ++ [
    yq
    yuicompressor
    z3
    zbar
    zfs-prune-snapshots
    zip
    zsh
    zsh-syntax-highlighting

    aider-chat
  ]
  ++ optPkg "guidellm"
  ++ [
    (lib.hiPrio llama-cpp)
  ]
  ++ optPkg "llama-swap"
  ++ optPkg "gguf-tools"
  ++ [
    openmpi
    qdrant
  ]
  ++ optPkg "qdrant-web-ui"
  ++ optPkg "pal-mcp-server"
  ++ optPkg "rustdocs-mcp-server"
  ++ lib.optionals isDarwin (optPkg "vllm-mlx")
  ++ optPkg "agnix"
  ++ optPkg "cozempic"
  ++ optPkg "context-hub"
  ++ optPkg "context7-mcp"
  ++ optPkg "playwright-mcp"
  ++ optPkg "github-mcp-server"
  ++ optPkg "claude-replay"
  ++ (
    if pkgs ? mcp-server-sequential-thinking then
      [ (lib.hiPrio pkgs.mcp-server-sequential-thinking) ]
    else
      [ ]
  )
  ++ [
    (exe git-annex)
    git-annex-remote-rclone
  ]
  # Linux-only packages (not available on Darwin/macOS)
  ++ lib.optionals isLinux (optPkg "cpx")
  ++ (
    if inputs ? llm-agents then
      (with inputs.llm-agents.packages.${sys}; [
        claude-code
        claude-code-acp
        ccusage
        droid
        opencode
        # gemini-cli
        # codex
        # ollama
      ])
    else
      [ ]
  )
  ++ lib.optionals (hostname == "hera") (
    [
      himalaya
      openai-whisper
      openhue-cli
      soco-cli
      spotify-player
    ]
    ++ (
      if inputs ? llm-agents then
        (with inputs.llm-agents.packages.${sys}; [
          mcporter
        ])
      else
        [ ]
    )
  );
}
