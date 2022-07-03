{ pkgs }:

with pkgs; let exe = haskell.lib.justStaticExecutables; in [
  (exe gitAndTools.git-annex)
  (exe haskellPackages.git-all)
  (exe haskellPackages.pushme)
  (exe haskellPackages.runmany)
  (exe haskellPackages.sizes)
  (exe haskellPackages.sitebuilder)
  (exe haskellPackages.una)
  (exe haskellPackages.git-monitor)
  (exe haskellPackages.hours)
  # Haskell tools
  (exe haskellPackages.lhs2tex)
  (exe haskellPackages.cabal-install)
  (exe haskellPackages.hpack)
  (exe haskellPackages.hasktags)
  (exe haskellPackages.threadscope)
  (exe haskellPackages.ghcup)
  # OnePassword-op
  apg
  aria2
  asciidoctor
  aspell
  aspellDicts.en
  backblaze-b2
  bandwhich
  bash-completion
  bashInteractive
  bat
  bats
  browserpass
  cacert
  cachix
  cbor-diag
  # (exe (import ~/kadena/chainweb-node {}))
  contacts
  coreutils
  csvkit
  ctop
  cvc4
  darwin.cctools
  dhall
  dhall-json
  diffstat
  diffutils
  direnv
  dirscan
  ditaa
  dnsutils
  dot2tex
  dovecot
  dovecot_pigeonhole
  doxygen
  emacs28Env
  emacsERCEnv
  entr
  exiv2
  fd
  fetchmail
  ffmpeg
  figlet
  findutils
  fontconfig
  fswatch
  fzf
  gawk
  ghi
  gist
  git-lfs
  git-scripts
  gitAndTools.delta
  gitAndTools.git-annex-remote-rclone
  gitAndTools.git-crypt
  gitAndTools.git-hub
  gitAndTools.git-imerge
  gitAndTools.git-secret
  gitAndTools.gitflow
  gitAndTools.hub
  gitAndTools.tig
  gitAndTools.topGit
  gitRepo
  gitstats
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
  html-tidy
  htop
  httpie
  httrack
  iftop
  imagemagickBig
  imapfilter
  imgcat
  inkscape.out
  iperf
  jdiskreport
  jiq
  jo
  jq
  killall
  kubectl
  ledgerPy2Env
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
  m-cli
  m4
  mercurialFull
  mitmproxy
  more
  mosh
  msmtp
  mtr
  multitail
  my-scripts
  mysql
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
  pdnsd
  perl
  perlPackages.ImageExifTool
  pinentry_mac
  plantuml
  poppler_utils
  postgresql
  procps
  projects-env
  prooftree
  protobufc
  pstree
  pv
  python27
  python27Packages.certifi
  python27Packages.pygments
  python27Packages.setuptools
  pythonDocs.html.python27
  pythonDocs.pdf_letter.python27
  python3
  python3Packages.numpy
  python3Packages.pandas
  pythonDocs.html.python37
  pythonDocs.pdf_letter.python37
  qemu #libvirt
  qpdf
  qrencode
  ratpoison
  rclone
  # recoll
  renameutils
  restic
  ripgrep
  rlwrap
  rsync
  # rtags
  ruby
  # rust-analyzer
  # rustup
  sbcl
  scc
  sccache
  screen
  sdcv
  shfmt
  sift
  sipcalc
  sloccount
  smartmontools
  socat
  sourceHighlight
  spiped
  sqlite
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
  tsvutils
  #unixtools.ifconfig
  #unixtools.netstat
  #unixtools.ping
  #unixtools.route
  #unixtools.top
  unrar
  unzip
  w3m
  wabt
  watch
  watchman
  wget
  wireguard-tools
  xapian
  xdg_utils
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
  zip
  znc
  zncModules.push
  zsh
  zsh-syntax-highlighting
]
