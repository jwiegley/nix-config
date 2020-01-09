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
  jo
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

  # (pkgs.myEnvFun {
  #    name = "ghc84";
  #    buildInputs = [ pkgs.haskellPackages_8_4.ghc ];
  #  })
  # (pkgs.myEnvFun {
  #    name = "ghc86";
  #    buildInputs = [ pkgs.haskellPackages_8_6.ghc ];
  #  })
  # (pkgs.myEnvFun {
  #    name = "ghc88";
  #    buildInputs = [ pkgs.haskellPackages_8_8.ghc ];
  #  })
  # (pkgs.myEnvFun {
  #    name = "ghc810";
  #    buildInputs = [ pkgs.haskellPackages_8_10.ghc ];
  #  })

  # (pkgs.myEnvFun {
  #    name = "coq86";
  #    buildInputs = [ pkgs.coqPackages_8_6.coq ];
  #  })
  # (pkgs.myEnvFun {
  #    name = "coq87";
  #    buildInputs = [ pkgs.coqPackages_8_7.coq ];
  #  })
  # (pkgs.myEnvFun {
  #    name = "coq88";
  #    buildInputs = [ pkgs.coqPackages_8_8.coq ];
  #  })
  # (pkgs.myEnvFun {
  #    name = "coq89";
  #    buildInputs = [ pkgs.coqPackages_8_9.coq ];
  #  })
  # (pkgs.myEnvFun {
  #    name = "coq810";
  #    buildInputs = [ pkgs.coqPackages_8_10.coq ];
  #  })

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
  wireshark
  youtube-dl
  znc
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
  # cachix
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
  pass
  # (pass.withExtensions (ext: with ext; [ pass-update pass-import ]))
  pass-git-helper
  perl
  browserpass
  qrencode
  pinentry_mac
  (exe (import ~/src/pushme {}))
  procps
  pstree
  pv
  qemu
  renameutils
  ripgrep
  rlwrap
  ruby
  (exe (import ~/src/runmany {}))
  screen
  (exe (import ~/src/sizes {}))
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
  (exe (import ~/src/una {}))
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
