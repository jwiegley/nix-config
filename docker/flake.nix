{
  description = "Sandboxed development environment Docker image (pure Nix, no host access)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          inherit (pkgs) lib;

          # ─── Package Categories ──────────────────────────────────────
          #
          # Curated from ~/src/nix/config/packages.nix, filtered for:
          #   - Linux compatibility (no Darwin-specific packages)
          #   - Available in vanilla nixpkgs (no overlay or local flake input packages)
          #   - No credential/secret dependencies baked in

          shellAndTerminal = with pkgs; [
            bashInteractive
            bash-completion
            zsh
            zsh-autosuggestions
            zsh-syntax-highlighting
            tmux
            screen
            vim
            less
            more
            tree
            watch
            entr
          ];

          promptAndNavigation = with pkgs; [
            starship
            fzf
            direnv
            nix-direnv
            zoxide
            carapace
          ];

          fileManagement = with pkgs; [
            coreutils
            findutils
            ripgrep
            fd
            bat
            eza
            delta
            nnn
            yazi
            rsync
            rclone
            restic
            trash-cli
            fdupes
            dust
            fpart
            renameutils
            srm
            stow
          ];

          textProcessing = with pkgs; [
            gnugrep
            gnused
            gawk
            gnutar
            jq
            yq
            csvkit
            jo
            fx
            parallel
            diffstat
            diffutils
          ];

          gitAndVCS = with pkgs; [
            git
            gh
            hub
            tig
            subversion
            gist
            git-lfs
            git-absorb
            git-autofixup
            git-branchless
            git-cliff
            git-crypt
            git-delete-merged-branches
            (lib.lowPrio git-fame)
            git-filter-repo
            git-gone
            git-imerge
            git-machete
            mergiraf
            git-octopus
            git-quick-stats
            git-recent
            git-reparent
            git-repo
            git-series
            git-sizer
            (lib.hiPrio git-standup)
            git-subrepo
            git-vendor
            git-when-merged
            git-workspace
            gitRepo
            gitflow
            gitstats
            git-annex
            git-annex-remote-rclone
          ];

          networkTools = with pkgs; [
            curl
            wget
            openssh
            httpie
            aria2
            nmap
            socat
            mtr
            iperf3
            autossh
            dnsutils
            sipcalc
            fping
            w3m
            lftp
            httrack
          ];

          pythonEnv = with pkgs; [
            (lib.hiPrio (
              python3.withPackages (
                pp: with pp; [
                  autoflake
                  black
                  ruff
                  flake8
                  isort
                  numpy
                  pandas
                  pylint
                  requests
                ]
              )
            ))
            pyright
            uv
          ];

          nodeEnv = with pkgs; [
            nodejs_22
            pnpm
          ];

          devTools = with pkgs; [
            ruby
            jdk
            cmake
            pkg-config
            just
            lefthook
            gnumake
            gnuplot
            doxygen
            universal-ctags
            (lib.lowPrio ctags)
            tree-sitter
            shfmt
            scc
            sccache
            act
            wabt
          ];

          haskellTools = with pkgs; [
            haskellPackages.hasktags
            haskellPackages.hpack
            (lib.hiPrio haskellPackages.ormolu)
            haskellPackages.pointfree
          ];

          nixTools = with pkgs; [
            nix-diff
            nix-tree
            nixfmt
            deadnix
            statix
            nix-prefetch-git
            nix-index
          ];

          systemMonitoring = with pkgs; [
            htop
            btop
            procps
            pstree
            lsof
            pv
            bandwhich
            ctop
          ];

          dataAndDatabases = with pkgs; [
            sqlite
            sqlite-analyzer
            sqldiff
          ];

          documentProcessing = with pkgs; [
            pandoc
            aspell
            aspellDicts.en
            highlight
            groff
            asciidoctor
            plantuml
            graphviz-nox
            librsvg
            poppler-utils
            pdfgrep
            html-tidy
            dot2tex
            ditaa
          ];

          mediaTools = with pkgs; [
            imagemagickBig
            ffmpeg
            exiv2
            (perl.withPackages (pp: with pp; [ ImageExifTool ]))
          ];

          archiveTools = with pkgs; [
            p7zip
            unzip
            unrar
            zip
            xz
            lzip
            lzop
            squashfsTools
          ];

          securityAndCrypto = with pkgs; [
            openssl
            mkcert
            qrencode
            nss
          ];

          cloudAndInfra = with pkgs; [
            awscli2
            google-cloud-sdk
            kubectl
          ];

          aiTools = with pkgs; [
            aider-chat
            (lib.hiPrio llama-cpp)
          ];

          miscUtilities = with pkgs; [
            apg
            b3sum
            backblaze-b2
            cacert
            cargo-cache
            figlet
            fontconfig
            fswatch
            getopt
            libxml2
            libxslt
            lnav
            m4
            multitail
            patch
            patchutils
            pcre
            protobufc
            pv
            qpdf
            rlwrap
            sdcv
            sourceHighlight
            tealdeer
            time
            translate-shell
            xapian
            yamale
            z3
          ];

          allPackages =
            shellAndTerminal
            ++ promptAndNavigation
            ++ fileManagement
            ++ textProcessing
            ++ gitAndVCS
            ++ networkTools
            ++ pythonEnv
            ++ nodeEnv
            ++ devTools
            ++ haskellTools
            ++ nixTools
            ++ systemMonitoring
            ++ dataAndDatabases
            ++ documentProcessing
            ++ mediaTools
            ++ archiveTools
            ++ securityAndCrypto
            ++ cloudAndInfra
            ++ aiTools
            ++ miscUtilities;

          # Merged environment — single PATH entry for all packages
          devEnv = pkgs.buildEnv {
            name = "devenv-packages";
            paths = allPackages;
            pathsToLink = [
              "/bin"
              "/lib"
              "/share"
              "/etc"
              "/include"
            ];
          };

          # ─── Configuration Files ─────────────────────────────────────
          #
          # Sanitized versions of ~/src/nix/config/home.nix settings.
          # Secrets, GPG signing, credential helpers, and host-specific
          # paths are deliberately excluded.

          gitconfigFile = pkgs.writeText "gitconfig" ''
            [user]
            	name = John Wiegley
            	email = johnw@newartisans.com
            [core]
            	editor = vim
            	pager = ${pkgs.less}/bin/less --tabs=4 -RFX
            	trustctime = false
            	logAllRefUpdates = true
            	precomposeunicode = false
            	whitespace = trailing-space,space-before-tab
            [alias]
            	amend = commit --amend -C HEAD
            	b = branch --color -v
            	ca = commit --amend
            	changes = diff --name-status -r
            	clone = clone --recursive
            	co = checkout
            	cp = cherry-pick
            	dc = diff --cached
            	dh = diff HEAD
            	ds = diff --staged
            	from = !git bisect start && git bisect bad HEAD && git bisect good
            	ls-ignored = ls-files --exclude-standard --ignored --others
            	rc = rebase --continue
            	rh = reset --hard
            	ri = rebase --interactive
            	rs = rebase --skip
            	ru = remote update --prune
            	snap = !git stash && git stash apply
            	spull = !git stash && git pull && git stash pop
            	su = submodule update --init --recursive
            	unstage = reset --soft HEAD^
            	w = status -sb
            	wr = worktree remove
            	wdiff = diff --color-words
            	l = log --graph --pretty=format:'%Cred%h%Creset —%Cblue%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative --show-notes=*
            [branch]
            	autosetupmerge = true
            [commit]
            	status = false
            [github]
            	user = jwiegley
            [pull]
            	rebase = true
            [rebase]
            	autosquash = true
            [init]
            	defaultBranch = main
            [push]
            	autoSetupRemote = true
            	default = simple
            [merge]
            	conflictstyle = diff3
            	stat = true
            [merge "mergiraf"]
            	name = mergiraf
            	driver = ${pkgs.mergiraf}/bin/mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L
            [color]
            	status = auto
            	diff = auto
            	branch = auto
            	interactive = auto
            	ui = auto
            [diff]
            	ignoreSubmodules = dirty
            	renames = copies
            	mnemonicprefix = true
            [advice]
            	statusHints = false
            	pushNonFastForward = false
            	objectNameWarning = false
            [http]
            	sslCAinfo = ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            	sslverify = true
            [filter "lfs"]
            	clean = git-lfs clean -- %f
            	smudge = git-lfs smudge --skip -- %f
            	required = true
          '';

          gitignoreFile = pkgs.writeText "gitignore-global" ''
            #*#
            *.a
            *.agdai
            *.aux
            *.dylib
            *.elc
            *.glob
            *.hi
            *.la
            *.o
            *.so
            *~
            .*.aux
            .DS_Store
            .direnv/
            .envrc
            .envrc.cache
            .envrc.override
            TAGS
            dist-newstyle/
            result
            result-*
            tags
          '';

          gitattributesFile = pkgs.writeText "gitattributes-global" (
            lib.concatMapStringsSep "\n"
              (ext: "${ext} merge=mergiraf")
              [
                "*.java"
                "*.rs"
                "*.go"
                "*.js"
                "*.jsx"
                "*.mjs"
                "*.ts"
                "*.tsx"
                "*.py"
                "*.rb"
                "*.c"
                "*.h"
                "*.cpp"
                "*.hpp"
                "*.nix"
                "*.json"
                "*.yml"
                "*.yaml"
                "*.toml"
                "*.html"
                "*.htm"
                "*.xml"
                "*.md"
                "*.hs"
                "*.lua"
                "*.ex"
                "*.exs"
                "*.cs"
                "*.dart"
                "*.scala"
                "*.php"
                "*.mk"
                "Makefile"
                "GNUmakefile"
                "CMakeLists.txt"
                "*.cmake"
              ]
          );

          starshipConfigFile = pkgs.writeText "starship.toml" ''
            add_newline = true
            scan_timeout = 50
            command_timeout = 1000

            format = """
            ($all
            )$directory$character"""

            [line_break]
            disabled = true

            [character]
            success_symbol = "[\\$](bold green)"
            error_symbol = "[\\$](bold red)"
          '';

          zshrcFile = pkgs.writeText "zshrc" ''
            # ── History ────────────────────────────────────────────────
            HISTSIZE=50000
            SAVEHIST=500000
            HISTFILE="$HOME/.zsh_history"
            setopt HIST_IGNORE_DUPS SHARE_HISTORY APPEND_HISTORY EXTENDED_HISTORY

            # ── Key bindings ───────────────────────────────────────────
            bindkey -e
            bindkey '^T' transpose-chars

            # ── Completion ─────────────────────────────────────────────
            autoload -Uz compinit && compinit

            # ── Shell options ──────────────────────────────────────────
            setopt extended_glob

            # ── Environment ────────────────────────────────────────────
            export EDITOR=vim
            export PAGER=less
            export LESS="-FRSXM"
            export LESSCHARSET=utf-8
            export LC_CTYPE=en_US.UTF-8
            export CLICOLOR=yes
            export TZ=PST8PDT
            export WORDCHARS=""
            export LEDGER_COLOR=true
            export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --info=inline --border --exact"

            # ── Aliases ────────────────────────────────────────────────
            alias vi=vim
            alias b='git b'
            alias l='git l'
            alias w='git w'
            alias ga='git-annex'
            alias par='parallel'
            alias rX='chmod -R ugo+rX'
            alias scp='rsync -aP --inplace'
            alias rehash='hash -r'
            alias cb='cabal build'
            alias cn='cabal configure --enable-tests --enable-benchmarks'

            # ── Tool initialization ────────────────────────────────────
            eval "$(${pkgs.starship}/bin/starship init zsh)"
            eval "$(${pkgs.fzf}/bin/fzf --zsh)"
            eval "$(${pkgs.direnv}/bin/direnv hook zsh)"
            eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
            eval "$(${pkgs.carapace}/bin/carapace _carapace zsh)"

            # ── Plugins (must be last) ─────────────────────────────────
            source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
            source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
          '';

          tmuxConfFile = pkgs.writeText "tmux.conf" ''
            set-option -g default-shell ${pkgs.zsh}/bin/zsh
            set-option -g default-command ${pkgs.zsh}/bin/zsh
            set-option -g history-limit 250000
            set-option -g mouse on
            set-option -g set-titles on
            set-option -g set-titles-string "#{b:pane_current_path}"
            set-option -g automatic-rename on
            set-option -g automatic-rename-format "#{b:pane_current_path}"
          '';

        in
        {
          # ─── Docker Image ──────────────────────────────────────────
          #
          # Build:  nix build .#devenv-image
          # Load:   docker load < result
          # Run:    docker run -it --rm \
          #           --cap-drop=ALL \
          #           --security-opt no-new-privileges \
          #           -v "$(pwd):/home/johnw/workspace" \
          #           devenv:latest
          #
          # For complete isolation (no network):
          #   docker run -it --rm --network none ...

          devenv-image = pkgs.dockerTools.buildLayeredImage {
            name = "devenv";
            tag = "latest";
            maxLayers = 120;

            contents = [ devEnv ];

            # extraCommands runs in the customisation layer directory.
            # Paths are RELATIVE (no leading /) to the layer root.
            # We use this instead of fakeRootCommands because proot
            # doesn't work reliably in NixOS's strict build sandbox.
            extraCommands = ''
              # ── System files ─────────────────────────────────────
              mkdir -p etc

              cat > etc/passwd <<EOF
              root:x:0:0:root:/root:/bin/sh
              nobody:x:65534:65534:Nobody:/nonexistent:/usr/sbin/nologin
              johnw:x:1000:1000:John Wiegley:/home/johnw:${pkgs.zsh}/bin/zsh
              EOF

              cat > etc/group <<EOF
              root:x:0:
              nogroup:x:65534:
              johnw:x:1000:johnw
              EOF

              echo "hosts: files dns" > etc/nsswitch.conf

              # ── Shell compatibility symlinks ──────────────────────
              mkdir -p bin usr/bin
              ln -sf ${pkgs.bashInteractive}/bin/bash bin/sh
              ln -sf ${pkgs.bashInteractive}/bin/bash bin/bash
              ln -sf ${pkgs.coreutils}/bin/env usr/bin/env

              # ── Home directory structure ──────────────────────────
              mkdir -p home/johnw/.config/git
              mkdir -p home/johnw/.config/starship
              mkdir -p home/johnw/.config/zsh
              mkdir -p home/johnw/.cache
              mkdir -p home/johnw/.local/share
              mkdir -p home/johnw/workspace

              # Git configuration (sanitized — no GPG, no credential helper)
              cp ${gitconfigFile} home/johnw/.gitconfig
              cp ${gitignoreFile} home/johnw/.config/git/ignore
              cp ${gitattributesFile} home/johnw/.config/git/attributes

              # Shell configuration
              cp ${zshrcFile} home/johnw/.zshrc
              cp ${starshipConfigFile} home/johnw/.config/starship.toml

              # Tmux configuration
              cp ${tmuxConfFile} home/johnw/.tmux.conf

              # ── Permissions ────────────────────────────────────────
              # extraCommands creates files owned by root.  The container
              # runs as uid 1000 (johnw), so the home tree must be
              # world-writable.  Single-user container — this is safe.
              chmod -R 777 home/johnw

              mkdir -p tmp
              chmod 1777 tmp
            '';

            config = {
              Cmd = [ "${pkgs.zsh}/bin/zsh" ];
              User = "johnw";
              WorkingDir = "/home/johnw";
              Env = [
                "PATH=${devEnv}/bin:/usr/local/bin:/usr/bin:/bin"
                "HOME=/home/johnw"
                "USER=johnw"
                "SHELL=${pkgs.zsh}/bin/zsh"
                "TERM=xterm-256color"
                "LANG=C.UTF-8"
                "TZ=PST8PDT"
                "TZDIR=${pkgs.tzdata}/share/zoneinfo"
                "EDITOR=vim"
                "PAGER=less"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "STARSHIP_CONFIG=/home/johnw/.config/starship.toml"
                "XDG_CONFIG_HOME=/home/johnw/.config"
                "XDG_DATA_HOME=/home/johnw/.local/share"
                "XDG_CACHE_HOME=/home/johnw/.cache"
                "CLICOLOR=yes"
                "FZF_DEFAULT_OPTS=--height 40% --layout=reverse --info=inline --border --exact"
              ];
              Volumes = {
                "/home/johnw/workspace" = { };
              };
              Labels = {
                "org.opencontainers.image.description" = "Sandboxed development environment — no host access";
                "org.opencontainers.image.source" = "https://github.com/jwiegley/nix-config";
              };
            };
          };

          # Convenience alias
          default = self.packages.${system}.devenv-image;
        }
      );
    };
}
