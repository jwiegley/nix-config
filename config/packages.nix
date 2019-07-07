{ pkgs }:

with pkgs; let exe = haskell.lib.justStaticExecutables; in [
  nixStable
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
  (exe haskPkgs.git-all)        # jww (2019-03-07): use a direct import
  (exe haskPkgs.git-monitor)    # jww (2019-03-07): use a direct import
  git-lfs
  # git-pull-request
  git-scripts
  git-subrepo
  git-tbdiff
  gitRepo
  gitAndTools.git-crypt
  gitAndTools.git-imerge
  gitAndTools.gitFull
  gitAndTools.gitflow
  gitAndTools.hub
  gitAndTools.tig
  gitAndTools.topGit
  (exe gitAndTools.git-annex)
  gitAndTools.git-annex-remote-rclone
  gitAndTools.git-secret
  gitstats
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

  # langToolsEnv
  (exe haskPkgs.cabal-install)  # for sdist/publish
  direnv
  global
  gnumake
  (exe haskPkgs.hpack)
  # (exe haskPkgs.brittany)
  # (exe (import ~/src/hnix {}))
  htmlTidy
  m4
  idutils
  rtags
  sloccount
  valgrind
  wabt
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
  go-jira
  httpie
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
  wireshark
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
  ledger_HEAD
  (exe haskPkgs.lhs2tex)
  librsvg
  pandoc
  pdf-tools-server
  plantuml
  poppler_utils
  recoll
  qpdf
  perlPackages.ImageExifTool
  libxml2
  libxslt
  sdcv
  (exe (import ~/src/sitebuilder {}))
  sourceHighlight
  svg2tikz
  taskjuggler
  texFull
  # texinfo
  xapian
  xdg_utils
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
  (exe (import ~/src/hours {}))
  htop
  imagemagickBig
  imgcat
  jdiskreport
  jdk8
  less
  linkdups
  lipotell
  # lorri
  m-cli
  multitail
  mysql
  nix-bash-completions
  nix-zsh-completions
  nix-diff
  org2tc
  p7zip
  paperkey
  parallel
  (pass.withExtensions (ext: with ext; [ pass-update pass-import ]))
  pass-git-helper
  browserpass
  qrencode
  pinentry_mac
  (exe (import ~/src/pushme {}))
  pstree
  pv
  qemu
  renameutils
  ripgrep
  rlwrap
  (exe (import ~/src/runmany {}))
  screen
  (exe (import ~/src/sizes {}))
  smartmontools
  sqlite
  srm
  stow
  terminal-notifier
  time
  tmux
  tree
  tsvutils
  (exe (import ~/src/una {}))
  unrar
  unzip
  vim
  watch
  watchman
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
  prooftree

  # Applications
  Anki
  Dash
  Docker
  Firefox
  GIMP
  HandBrake
  iTerm2
  KeyboardMaestro
  PathFinder
  RipIt
  Skim
  Slate
  Soulver
  SuspiciousPackage
  Ukelele
  UnicodeChecker
  VirtualII
  Zekr
  Zotero
]
