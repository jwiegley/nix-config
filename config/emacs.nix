pkgs: epkgs:
let exclude = p: p // { excluded = true; }; in
with epkgs; [
  epkgs."2048-game"
  ace-mc
  ace-window
  adoc-mode
  agda2-mode
  aggressive-indent
  aider
  (exclude aio)
  (exclude all-the-icons)
  (exclude anki-editor)
  aria2
  ascii
  async
  auctex
  auto-yasnippet
  avy
  avy-embark-collect
  avy-zap
  (exclude awesome-tray)
  (exclude backup-each-save)
  (exclude backup-walker)
  (exclude beacon)
  biblio
  bm
  boogie-friends
  (exclude bookmark-plus)
  (exclude browse-at-remote)
  browse-kill-ring
  (exclude buffer-terminator)
  (exclude bufler)
  burly
  (exclude calfw)
  (exclude calfw-cal)
  (exclude calfw-org)
  cape
  cargo
  (exclude centaur-tabs)
  (exclude centered-cursor-mode)
  change-inner
  citar
  citar-embark
  (exclude citar-org-node)
  citar-org-roam
  (exclude citre)
  cmake-font-lock
  cmake-mode
  col-highlight
  color-moccur
  color-theme
  command-log-mode
  (exclude company)
  company-coq
  (exclude company-math)
  (exclude compile-angel)
  consult
  consult-company
  consult-dir
  consult-eglot-embark
  (exclude consult-flycheck)
  consult-gh
  consult-gh-embark
  consult-gh-forge
  consult-gh-with-pr-review
  (exclude consult-git-log-grep)
  consult-hoogle
  (exclude consult-lsp)
  consult-omni
  consult-org-roam
  consult-projectile
  consult-yasnippet
  copy-as-format
  corfu
  (exclude corfu-prescient)
  corsair
  crosshairs
  (exclude crux)
  csv-mode
  (exclude ctrlf)
  (exclude cursor-chg)
  dash
  deadgrep
  dedicated
  diff-hl
  diffview
  diminish
  dired-hist
  dired-rsync
  dired-subtree
  dired-toggle
  diredfl
  direnv
  discover-my-major
  docker
  docker-compose-mode
  dockerfile-mode
  doxymacs
  (exclude dumb-jump)
  eager-state
  easky
  easy-kill
  (exclude easysession)
  eat
  (exclude ebdb)
  edbi
  edit-env
  edit-indirect
  edit-server
  edit-var
  eglot
  eglot-booster
  el-job
  elisp-depend
  elisp-docstring-mode
  elisp-slime-nav
  elmacro
  elpy
  emamux
  embark
  embark-consult
  embark-org-roam
  emojify
  (exclude engine-mode)
  (exclude erc)
  (exclude erc-highlight-nicknames)
  (exclude erc-yank)
  eshell-bookmark
  eshell-up
  eshell-z
  (exclude eval-expr)
  evil
  eww-plz
  exec-path-from-shell
  expand-region
  eyebrowse
  f
  feebleline
  fence-edit
  (exclude flycheck)
  (exclude flycheck-haskell)
  focus
  font-lock-studio
  forge
  free-keys
  fsrs
  (exclude fullframe)
  ghub
  git-link
  git-timemachine
  (exclude git-undo)
  (exclude gitpatch)
  gnus-alias
  gnus-harvest
  gnus-recent
  (exclude google-this)
  goto-last-change
  gptel
  (exclude gptel-aibo)
  gptel-fn-complete
  (exclude gptel-got)
  gptel-quick
  graphviz-dot-mode
  (exclude hammy)
  haskell-mode
  hcl-mode
  helpful
  highlight
  highlight-cl
  highlight-defined
  highlight-numbers
  highlight-quoted
  hl-line-plus
  (exclude hl-todo)
  hydra
  ialign
  (exclude iedit)
  (exclude iflipb)
  imenu-list
  indent-shift
  inheritenv
  (exclude inhibit-mouse)
  inspector
  ipcalc
  jinx
  (exclude jobhours)
  jq-mode
  js2-mode
  json-mode
  json-reformat
  json-snatcher
  (exclude jupyter)
  just-mode
  key-chord
  keypression
  know-your-http-well
  language-id
  lasgun
  ledger-mode
  link-hint
  lispy
  listen
  literate-calc-mode
  lively
  llama
  (exclude lsp-bridge)
  (exclude lsp-haskell)
  (exclude lsp-mode)
  (exclude lsp-ui)
  lua-mode
  macher
  macrostep
  magit
  (exclude magit-annex)
  (exclude magit-imerge)
  (exclude magit-lfs)
  magit-popup
  magit-tbdiff
  magit-todos
  major-mode-hydra
  malyon
  marginalia
  markdown-mode
  markdown-preview-mode
  math-symbol-lists
  mc-calc
  mc-extras
  mediawiki
  memory-usage
  (exclude mic-paren)
  minesweeper
  (exclude minimap)
  moccur-edit
  (exclude monitor)
  move-text
  multi-term
  multi-vterm
  multifiles
  multiple-cursors
  (exclude names)
  nginx-mode
  nix-mode
  nov
  (exclude oauth2)
  ob-emamux
  ob-restclient
  olivetti
  onepassword-el
  operate-on-number
  orderless
  org
  (exclude org-alert)
  org-anki
  org-annotate
  org-appear
  org-auto-expand
  org-autolist
  org-bookmark-heading
  (exclude org-caldav)
  org-checklist
  org-contacts
  org-drill
  org-edna
  org-extra-emphasis
  (exclude org-fancy-priorities)
  (exclude org-gcal)
  org-margin
  (exclude org-mem)
  org-mime
  (exclude org-ml)
  (exclude org-modern)
  org-mru-clock
  (exclude org-msg)
  (exclude org-node)
  org-noter
  org-pdftools
  org-pretty-table
  org-project-capture
  org-projectile
  org-ql
  org-quick-peek
  org-real
  (exclude org-recent-headings)
  (exclude org-recoll)
  org-remark
  org-reverse-datetree
  org-review
  org-rich-yank
  org-roam
  org-roam-ui
  org-sidebar
  (exclude org-sql)
  org-srs
  org-sticky-header
  org-super-agenda
  org-superstar
  org-table-color
  org-table-highlight
  org-tidy
  (exclude org-timeline)
  org-transclusion
  (exclude org-upcoming-modeline)
  org-vcard
  org-web-tools
  orgit
  orgit-forge
  (exclude origami)
  (exclude osm)
  outline-indent
  (exclude ovpn-mode)
  (exclude ox-gfm)
  ox-pandoc
  (exclude ox-slack)
  (exclude ox-texinfo-plus)
  ox-whatsapp
  p-search
  package-lint
  pact-mode
  pandoc-mode
  paradox
  paredit
  parse-csv
  pass
  password-store
  pcre2el
  pdf-tools
  pdfgrep
  persistent-scratch
  persistent-soft
  pg
  pgmacs
  (exclude phi-search)
  (exclude phi-search-mc)
  plantuml-mode
  plz
  (exclude po-mode)
  (exclude popper)
  popup-ruler
  pp-c-l
  (exclude prescient)
  pretty-hydra
  prodigy
  projectile
  proof-general
  protobuf-mode
  python-mode
  quick-peek
  rainbow-delimiters
  rainbow-mode
  redshank
  regex-tool
  (exclude repl-toggle)
  restclient
  riscv-mode
  rs-gnus-summary
  rust-mode
  s
  sbt-mode
  scala-mode
  sdcv-mode
  selected
  separedit
  (exclude shackle)
  shell-maker
  shell-toggle
  shift-number
  sky-color-clock
  (exclude slack)
  slime
  (exclude smart-mode-line)
  smart-newline
  smartparens
  (exclude smartscan)
  (exclude sops)
  sort-words
  sql-indent
  string-inflection
  sudo-edit
  (exclude sunrise-commander)
  (exclude super-save)
  supercite
  swift-mode
  tagedit
  templatel
  terraform-mode
  tidy
  timeout
  tla-mode
  toc-org
  transpose-mark
  tree-inspector
  treemacs
  tuareg
  typescript-mode
  typo
  ultra-scroll-mac
  (exclude undo-fu)
  undo-propose
  unicode-fonts
  uniline
  uuidgen
  vagrant
  vagrant-tramp
  vcard-mode
  vdiff
  (exclude verb)
  vertico
  (exclude vertico-prescient)
  vimish-fold
  virtual-auto-fill
  visual-fill-column
  visual-regexp
  (exclude visual-regexp-steroids)
  vline
  vterm
  (exclude vterm-tmux)
  vulpea
  vundo
  w3m
  wat-mode
  web
  web-mode
  wgrep
  (exclude which-key)
  whitespace-cleanup-mode
  window-purpose
  word-count-mode
  writeroom-mode
  (exclude x86-lookup)
  (exclude xeft)
  xr
  xray
  yaml-mode
  (exclude yaoddmuse)
  yasnippet
  z3-mode
  zoom
  ztree
]
