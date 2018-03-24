{ pkgs }:

with pkgs; let exe = haskell.lib.justStaticExecutables; in [
  nixUnstable
  nix-scripts
  nix-prefetch-scripts
  home-manager
  coreutils
  my-scripts

  # gitToolsEnv
  diffstat
  diffutils
  ghi
  gist
  (exe haskPkgs.git-all)
  (exe haskPkgs.git-monitor)
  git-lfs
  git-scripts
  git-tbdiff
  gitRepo
  gitAndTools.git-imerge
  gitAndTools.gitFull
  gitAndTools.gitflow
  gitAndTools.hub
  gitAndTools.tig
  gitAndTools.git-annex
  gitAndTools.git-annex-remote-rclone
  github-backup
  gitstats
  pass-git-helper
  patch
  patchutils
  sift

  # jsToolsEnv
  jq
  nodejs
  nodePackages.eslint
  nodePackages.csslint
  nodePackages.js-beautify
  nodePackages.jsontool

  # langToolsEnv
  R
  autoconf
  automake
  (exe haskPkgs.cabal2nix)
  (exe haskPkgs.cabal-install)
  (exe haskellPackages_8_0.hs-to-coq)
  clang
  cmake
  fftw
  fftw.dev
  fftw.man
  fftwFloat
  fftwFloat.dev
  fftwFloat.man
  fftwLongDouble
  fftwLongDouble.dev
  fftwLongDouble.man
  global
  gmp
  gnumake
  (exe haskPkgs.hpack)
  htmlTidy
  idutils
  lean
  libcxx
  libcxxabi
  libtool
  llvm
  lp_solve
  mpfr
  ninja
  ott
  pkgconfig
  rabbitmq-c
  rtags
  sbcl
  sloccount
  verasco
  yamale

  # mailToolsEnv
  contacts
  dovecot
  dovecot_pigeonhole
  fetchmail
  imapfilter
  leafnode
  msmtp

  # networkToolsEnv
  aria2
  backblaze-b2
  bazaar
  cacert
  dnsutils
  httrack
  iperf
  lftp
  mercurialFull
  # mitmproxy
  mtr
  nmap
  openssh
  openssl
  openvpn
  pdnsd
  rclone
  rsync
  sipcalc
  socat2pre
  spiped
  sshify
  subversion
  w3m
  wget
  youtube-dl
  znc
  zncModules.fish
  zncModules.push

  # publishToolsEnv
  biber
  ditaa
  dot2tex
  doxygen
  figlet
  fontconfig
  graphviz-nox
  groff
  highlight
  hugo
  inkscape.out
  ledger
  (exe haskPkgs.lhs2tex)
  librsvg
  (exe haskPkgs.pandoc)
  pdf-tools-server
  plantuml
  poppler_utils
  qpdf
  recoll
  perlPackages.ImageExifTool
  libxml2
  libxslt
  sdcv
  (exe haskPkgs.sitebuilder)
  sourceHighlight
  svg2tikz
  texFull
  # texinfo
  xapian
  xdg_utils
  wordnet
  yuicompressor

  # pythonToolsEnv
  python27
  pythonDocs.pdf_letter.python27
  pythonDocs.html.python27
  python27Packages.setuptools
  python27Packages.pygments
  python27Packages.certifi
  python3

  # systemToolsEnv
  aspell
  aspellDicts.en
  bash-completion
  bashInteractive
  browserpass
  dirscan
  ctop
  cvc4
  direnv
  epipe
  exiv2
  fd
  findutils
  fswatch
  fzf
  gawk
  gnugrep
  gnupg
  gnuplot
  gnused
  gnutar
  hammer
  hashdb
  (exe haskPkgs.hours)
  htop
  imagemagickBig
  jdiskreport
  jdk8
  less
  linkdups
  lipotell
  multitail
  mysql
  nix-bash-completions
  nix-zsh-completions
  org2tc
  p7zip
  paperkey
  parallel
  pass
  pass-otp
  pinentry_mac
  postgresql
  (exe haskPkgs.pushme)
  pv
  qemu
  qrencode
  renameutils
  ripgrep
  rlwrap
  (exe haskPkgs.runmany)
  screen
  silver-searcher
  (exe haskPkgs.simple-mirror)
  (exe haskPkgs.sizes)
  smartmontools
  sqlite
  srm
  stow
  terminal-notifier
  time
  tmux
  tree
  tsvutils
  (exe haskPkgs.una)
  unrar
  unzip
  vim
  watch
  xz
  yubico-piv-tool
  yubikey-manager
  yubikey-personalization
  z
  z3
  zbar
  zip
  zsh
  zsh-syntax-highlighting

  # x11ToolsEnv
  # xquartz
  # xorg.xhost
  # xorg.xauth
  # ratpoison

  # Applications
  Anki
  Dash
  DeskzillaLite
  Docker
  Firefox
  GIMP
  HandBrake
  KeyboardMaestro
  # LaTeXiT
  # LaunchBar
  OpenZFSonOSX
  PathFinder
  PhoneView
  RipIt
  #SageMath
  Skim
  Soulver
  SuspiciousPackage
  # Transmission
  Ukelele
  UnicodeChecker
  VLC
  VirtualII
  Zekr
  Zotero
  iTerm2
]
