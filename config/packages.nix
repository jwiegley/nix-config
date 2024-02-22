pkgs:

with pkgs; 

let exe = haskell.lib.justStaticExecutables; in 

[
  (exe gitAndTools.git-annex)
  # (exe haskellPackages.git-all)
  haskellPackages.pushme
  # (exe haskellPackages.runmany)
  (exe haskellPackages.sizes)
  haskellPackages.sitebuilder
  (exe haskellPackages.una)
  (exe haskellPackages.git-monitor)
  # (exe haskellPackages.hours)
  # (exe haskellPackages.cabal-install)
  # (exe haskellPackages.hpack)
  # (exe haskellPackages.hasktags)
  # (exe haskellPackages.eventlog2html)
  haskellPackages.ormolu
  # (exe (haskell.lib.doJailbreak haskellPackages_8_10.threadscope))
  (exe haskellPackages.pointfree)
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
  boogie
  cacert
  cbor-diag
  contacts
  coreutils
  csvkit
  ctop
  curl
  (pkgs.lowPrio dafny)
  darwin.cctools
  dhall
  dhall-json
  diffstat
  diffutils
  direnv
  ditaa
  dnsutils
  dot2tex
  dovecot
  dovecot_pigeonhole
  dovecot_fts_xapian
  doxygen
  emacs29MacPortEnv
  emacs29Env
  entr
  exiv2
  fd
  fdupes
  fetchmail
  ffmpeg
  figlet
  findutils
  fio
  fontconfig
  fping
  fswatch
  fzf
  gawk
  gitAndTools.delta
  gitAndTools.gh
  gitAndTools.ghi
  gitAndTools.gist
  gitAndTools.git-absorb
  gitAndTools.git-annex-remote-rclone
  gitAndTools.git-branchless
  gitAndTools.git-branchstack
  gitAndTools.git-cliff
  gitAndTools.git-codeowners
  gitAndTools.git-crypt
  gitAndTools.git-delete-merged-branches
  (pkgs.lowPrio gitAndTools.git-extras)
  gitAndTools.git-fame
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
  (pkgs.hiPrio gitAndTools.git-standup)
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
  home-manager
  hostname
  # hs-to-coq
  html-tidy
  htop
  httm
  httpie
  httrack
  iftop
  imagemagickBig
  imapfilter
  goimapnotify
  imgcat
  inkscape.out
  iperf
  isync
  jdk
  jiq
  jo
  jq
  jujutsu
  jupyter
  killall
  kubectl
  ledgerPy3Env
  ledger_HEAD
  less
  lftp
  librsvg
  libxml2
  libxslt
  linkdups
  lipotell
  lnav
  lsof
  lzip
  lzop
  m-cli
  m4
  mercurialFull
  metabase
  mitmproxy
  more
  mosh
  msmtp
  mtr
  multitail
  my-scripts
  nix-diff
  nix-index
  nix-info
  nix-prefetch-scripts
  nix-scripts
  nixStable
  nixpkgs-fmt
  nixfmt
  nmap
  node2nix
  nodePackages.csslint
  nodePackages.eslint
  nodePackages.js-beautify
  nodejs
  offlineimap
  opam
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
  perl
  perlPackages.ImageExifTool
  pinentry_mac
  plantuml
  pngpaste
  poppler_utils
  postgresql
  procps
  protobufc
  psrecord
  pstree
  pv
  (pkgs.lowPrio python3)
  qemu libvirt
  qpdf
  qrencode
  ratpoison
  rclone
  recoll
  renameutils
  restic
  ripgrep
  rlwrap
  rsync
  ruby
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
  sloccount
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
  (pkgs.lowPrio ctags)
  universal-ctags
  unixtools.ifconfig
  unixtools.netstat
  unixtools.ping
  unixtools.route
  unixtools.top
  unrar
  unzip
  w3m
  wabt
  watch
  watchman
  wget
  wireguard-tools
  xapian
  xdg-utils
  xorg.xauth
  xorg.xhost
  xquartz
  xsv
  xz
  yamale
  youtube-dl
  yq
  yuicompressor
  z
  z3
  zbar
  zfs-prune-snapshots
  zip
  znc
  zncModules.push
  zsh
  zsh-syntax-highlighting

  # Kadena packages
  # (pkgs.lowPrio pact)
  # (pkgs.lowPrio pact-lsp)
]

++

pkgs.lib.optionals pkgs.stdenv.targetPlatform.isx86_64 [
  emacsERCEnv
]
