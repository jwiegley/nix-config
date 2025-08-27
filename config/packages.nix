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
    (exe haskellPackages.ormolu)
    (exe haskellPackages.pointfree)
    # haskellPackages.git-all
    haskellPackages.git-monitor
    haskellPackages.hours
    haskellPackages.org-jw
    haskellPackages.pushme
    haskellPackages.renamer
    haskellPackages.sizes
    haskellPackages.trade-journal
    haskellPackages.una
    act
    apg
    aria2
    asciidoctor
    aspell
    aspellDicts.en
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
    ditaa
    dnstracer
    dnsutils
    dot2tex
    dovecot
    # dovecot_pigeonhole
    # dovecot_fts_xapian
    doxygen
    du-dust
    eask
    emacs30Env
    emacs30MacPortEnv
    emacsHEADEnv
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
    fio
    fontconfig
    fping
    fswatch
    fzf
    fzf-zsh
    gawk
    getopt
    gitAndTools.delta
    gitAndTools.gh
    gitAndTools.ghi
    gitAndTools.gist
    gitAndTools.git-absorb
    # gitAndTools.git-branchless
    gitAndTools.git-branchstack
    gitAndTools.git-cliff
    gitAndTools.git-crypt
    gitAndTools.git-delete-merged-branches
    (lowPrio gitAndTools.git-extras)
    (lowPrio gitAndTools.git-fame)
    gitAndTools.git-gone
    gitAndTools.git-hub
    gitAndTools.git-imerge
    gitAndTools.git-lfs
    gitAndTools.git-machete
    gitAndTools.git-my
    gitAndTools.git-octopus
    gitAndTools.git-quick-stats
    gitAndTools.git-quickfix
    gitAndTools.git-recent
    gitAndTools.git-reparent
    gitAndTools.git-repo
    gitAndTools.git-scripts
    gitAndTools.git-secret
    gitAndTools.git-series
    gitAndTools.git-sizer
    (hiPrio gitAndTools.git-standup)
    gitAndTools.git-subrepo
    gitAndTools.git-vendor
    gitAndTools.git-when-merged
    gitAndTools.git-workspace
    gitAndTools.gitRepo
    gitAndTools.gitflow
    gitAndTools.gitls
    gitAndTools.gitstats
    gitAndTools.hub
    gitAndTools.tig
    gitAndTools.top-git
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
    imagemagickBig
    imapfilter
    imgcat
    inkscape.out
    iperf
    isync
    jdk
    jiq
    jo
    jq
    jqp
    json2yaml
    jujutsu
    jupyter
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
    nur.repos.charmbracelet.crush
    nodejs_22
    nss
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
    poppler_utils
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
    (hiPrio
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
    sanoid
    sbcl
    scc
    sccache
    screen
    sdcv
    shfmt
    siege
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
    (lowPrio ctags)
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
    (hiPrio llama-cpp)
    llama-swap
    koboldcpp
    gguf-tools
    openmpi
    claude-code
    github-mcp-server
    rustdocs-mcp-server
    # mcp-server-fetch
    # mcp-server-filesystem
    # (hiPrio mcp-server-sequential-thinking)
    # mcp-server-memory
    # mcp-server-brave-search
    # mcp-server-gdrive
    # mcp-server-git
    # mcp-server-github
    # mcp-server-google-maps
    # mcp-server-postgres
    # mcp-server-slack
    # mcp-server-sqlite
    # mcp-server-time
    # mcp-server-qdrant
    qdrant
    qdrant-web-ui
    task-master-ai
  
    (exe gitAndTools.git-annex)
    gitAndTools.git-annex-remote-rclone
  ];
}
