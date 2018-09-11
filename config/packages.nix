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
  git-pull-request
  git-scripts
  git-tbdiff
  gitRepo
  gitAndTools.git-imerge
  gitAndTools.gitFull
  gitAndTools.gitflow
  gitAndTools.hub
  gitAndTools.tig
  (exe gitAndTools.git-annex)
  gitAndTools.git-annex-remote-rclone
  gitAndTools.git-secret
  (exe haskPkgs.github-backup)
  gitstats
  pass-git-helper
  patch
  patchutils
  sift
  travis

  # jsToolsEnv
  jq
  nodejs
  nodePackages.eslint
  nodePackages.csslint
  nodePackages.js-beautify
  nodePackages.jsontool

  # langToolsEnv
  R
  (exe haskPkgs.cabal-install)  # for sdist/publish
  direnv
  global
  gnumake
  (exe haskPkgs.hpack)
  htmlTidy
  idutils
  lp_solve
  rtags
  sloccount
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
  httpie
  httrack
  iperf
  lftp
  mercurialFull
  mitmproxy
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
  # biber                  # jww (2018-07-17): now part of texlive-combined
  ditaa
  dot2tex
  doxygen
  ffmpeg
  figlet
  fontconfig
  graphviz-nox
  groff
  highlight
  hugo
  inkscape.out
  ledger
  (exe haskellPackages_8_2.lhs2tex)
  librsvg
  (exe haskPkgs.pandoc)
  pdf-tools-server
  plantuml
  poppler_utils
  recoll
  qpdf
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
  apg
  aspell
  aspellDicts.en
  bash-completion
  bashInteractive
  bat
  browserpass
  dirscan
  ctop
  cvc4
  direnv
  entr
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
  imgcat
  jdiskreport
  jdk8
  less
  linkdups
  lipotell
  m-cli
  multitail
  mysql
  nix-bash-completions
  nix-zsh-completions
  org2tc
  p7zip
  paperkey
  parallel
  (pass.withExtensions (ext: with ext; [ pass-otp pass-update ]))
  pinentry_mac
  postgresql
  (exe haskPkgs.pushme)
  pv
  reflex
  qemu
  qrencode
  renameutils
  ripgrep
  rlwrap
  (exe haskPkgs.runmany)
  screen
  silver-searcher
  (exe haskellPackages_8_2.sizes)
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
  xsv
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
  xquartz
  xorg.xhost
  xorg.xauth
  ratpoison

  # Applications
  Anki
  Dash
  Docker
  Firefox
  GIMP
  HandBrake
  KeyboardMaestro
  # LaTeXiT
  # LaunchBar
  OpenZFSonOSX
  PathFinder
  RipIt
  # SageMath
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
