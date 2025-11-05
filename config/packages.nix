{ hostname, inputs, pkgs, ...}: with pkgs; rec
{
  exe = if stdenv.targetPlatform.isx86_64
        then haskell.lib.justStaticExecutables
        else lib.id;

  myEmacsPackages = import ./emacs.nix pkgs;

  emacs30Env = pkgs.emacs30Env (epkgs:
    (builtins.filter (x: !x.excluded or false) (myEmacsPackages epkgs)));
  emacs30MacPortEnv = pkgs.emacs30MacPortEnv (epkgs:
    (builtins.filter (x: !x.excluded or false) (myEmacsPackages epkgs)));
  emacsHEADEnv = pkgs.emacsHEADEnv myEmacsPackages;

  rag-client-pkg = import /Users/johnw/src/rag-client;
  rag-client = rag-client-pkg.packages.${pkgs.system}.default;

  package-list = [
    (exe haskellPackages.hasktags)
    (exe haskellPackages.hpack)
    (lib.hiPrio (exe haskellPackages.ormolu))
    (exe haskellPackages.pointfree)
    # haskellPackages.git-all
    haskellPackages.git-monitor
    haskellPackages.hours
    haskellPackages_9_10.org-jw
    haskellPackages_9_10.pushme
    haskellPackages_9_10.renamer
    haskellPackages_9_10.sizes
    haskellPackages_9_10.trade-journal
    haskellPackages_9_10.una
    act
    apg
    aria2
    asciidoctor
    aspell
    aspellDicts.en
    # awscli2
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
    fzf
    fzf-zsh
    gawk
    getopt
    delta
    gh
    gist
    git-absorb
    # git-branchless
    git-branchstack
    git-cliff
    git-crypt
    git-delete-merged-branches
    (lib.lowPrio git-extras)
    (lib.lowPrio git-fame)
    git-filter-repo
    git-gone
    git-hub
    git-imerge
    git-lfs
    git-machete
    git-my
    git-octopus
    git-quick-stats
    git-quickfix
    git-recent
    git-reparent
    git-repo
    git-scripts
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
    litellm
    lnav
    loccount
    lsof
    lzip
    lzop
    m-cli
    m4
    macmon
    mb2md
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
    nixfmt-classic
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
    (perl.withPackages (
      perl-pkgs: with perl-pkgs; [
        ImageExifTool
      ]))
    pinentry_mac
    pkg-config
    plantuml
    pngpaste
    pnpm
    poppler-utils
    (postgresql.withPackages (
      postgres-pkgs: with postgres-pkgs; [
        pgvector
      ]))
    libpq
    procmail
    procps
    protobufc
    psrecord
    pstree
    pv
    (lib.hiPrio
     (python3.withPackages (
       python-pkgs: with python-pkgs; [
         venvShellHook
         numpy
         requests
         stdenv
         # orgparse
         basedpyright
         autoflake
         pylint
         isort                    # Python code formatter
         black                    # Python code formatter
         flake8                   # Python code linter
         huggingface-hub
         hf-xet
       ])))
    pyright                       # LSP server for Python
    qdrant
    qemu libvirt
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
    # sbcl
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
    litellm
    (lib.hiPrio llama-cpp)
    llama-swap
    # koboldcpp
    gguf-tools
    openmpi
    claude-code
    qdrant
    qdrant-web-ui
    task-master-ai
    claude-code-acp
    rustdocs-mcp-server
  
    # mcp-servers-nix
    context7-mcp
    playwright-mcp
    github-mcp-server
    # mcp-server-filesystem
    # mcp-server-git
    mcp-server-memory
    (lib.hiPrio mcp-server-sequential-thinking)
    mcp-server-time
    # mcp-server-fetch

    (exe git-annex)
    git-annex-remote-rclone
  ];
}
