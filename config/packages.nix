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
  (exe haskPkgs.git-all)
  (exe haskellPackages_8_6.git-monitor)    # jww (2019-03-07): use a direct import
  git-lfs
  # git-pull-request
  git-scripts
  git-subrepo
  git-tbdiff
  gitstats
  gitRepo
  gitAndTools.git-crypt
  gitAndTools.git-hub
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
  yq
  jo
  nodejs
  nodePackages.eslint
  nodePackages.csslint
  nodePackages.js-beautify

  # langToolsEnv
  bats
  (exe haskPkgs.cabal-install)  # for sdist/publish
  direnv
  global
  gnumake
  (exe haskPkgs.hpack)
  htmlTidy
  m4
  rtags
  sloccount
  valgrind
  wabt
  yamale

  (pkgs.myEnvFun { name = "ghc84";  buildInputs = [ pkgs.haskellPackages_8_4.ghc ]; })
  (pkgs.myEnvFun { name = "ghc86";  buildInputs = [ pkgs.haskellPackages_8_6.ghc ]; })
  (pkgs.myEnvFun { name = "ghc88";  buildInputs = [ pkgs.haskellPackages_8_8.ghc ]; })
  (pkgs.myEnvFun { name = "ghc810"; buildInputs = [ pkgs.haskellPackages_8_10.ghc ]; })

  (pkgs.myEnvFun { name = "coq86";  buildInputs = [ pkgs.coqPackages_8_6.coq ]; })
  (pkgs.myEnvFun { name = "coq87";  buildInputs = [ pkgs.coqPackages_8_7.coq ]; })
  (pkgs.myEnvFun { name = "coq88";  buildInputs = [ pkgs.coqPackages_8_8.coq ]; })
  (pkgs.myEnvFun { name = "coq89";  buildInputs = [ pkgs.coqPackages_8_9.coq ]; })
  (pkgs.myEnvFun { name = "coq810"; buildInputs = [ pkgs.coqPackages_8_10.coq ]; })
  (pkgs.myEnvFun { name = "coq811"; buildInputs = [ pkgs.coqPackages_8_11.coq ]; })

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
  mitmproxy
  mosh
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
  wireguard
  youtube-dl
  znc
  zncModules.push

  # publishToolsEnv
  ditaa
  dot2tex
  doxygen
  ffmpeg
  figlet
  fontconfig
  graphviz-nox
  groff
  highlight
  inkscape.out
  ledger_HEAD
  (exe haskPkgs.lhs2tex)
  librsvg
  pandoc
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
  taskjuggler
  texFull
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
  # cachix
  # ctop
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
  (exe haskellPackages_8_6.hours)
  htop
  iftop
  imagemagickBig
  imgcat
  jdiskreport
  jdk8
  # minikube
  kubectl
  less
  linkdups
  lipotell
  lnav
  lsof
  m-cli
  multitail
  mysql
  nix-bash-completions
  nix-zsh-completions
  nix-diff
  nix-index
  nix-info
  OnePassword-op
  org2tc
  p7zip
  paperkey
  parallel
  (pass.withExtensions (ext: with ext; [ pass-otp pass-audit pass-genphrase ]))
  pass-git-helper
  perl
  browserpass
  qrencode
  pinentry_mac
  (exe haskPkgs.pushme)
  procps
  pstree
  pv
  qemu
  renameutils
  ripgrep
  rlwrap
  ruby
  (exe haskPkgs.runmany)
  screen
  (exe haskPkgs.sizes)
  smartmontools
  sqlite
  squashfsTools
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
  watchman
  xsv
  xz
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
]
