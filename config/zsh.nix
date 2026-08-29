{
  pkgs,
  lib,
  config,
  vars,
  ...
}:
let
  inherit (vars) isDarwin isLinux;

  # Follow the shared option declared in config/git-options.nix so one override
  # retargets the Git-backed aliases and Git configuration together.
  gitPkg = config.johnw.git.package;

  dotDir = "${config.xdg.configHome}/zsh";
  itermSource = (import ../packages/source-catalog.nix "tools").iterm2-shell-integration;
  scriptsPath = "${vars.home}/src/scripts";
  scriptsFirst = ''
    typeset -U path PATH
    path=("${scriptsPath}" ''${path:#${scriptsPath}})
    export PATH
  '';
in
{
  # Import the host capability option this module reads rather than relying on a
  # parent module's import list.
  imports = [ ./host-options.nix ];

  programs.bash = {
    enable = true;
    bashrcExtra = lib.mkBefore ''
      source /etc/bashrc
    '';
  };

  programs.zsh = {
    inherit dotDir;

    enable = true;
    enableCompletion = lib.mkDefault true;
    completionInit = lib.mkIf isDarwin ''
      fpath=(${lib.escapeShellArg "${dotDir}/completions"} $fpath)
      autoload -Uz compinit
      compinit -C
    '';

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = if config.johnw.host.isSharedWork then 600000 else 500000;
      save = 500000;
      # The work hosts share one NFS home.  Give each NFS client one history
      # file so a stale shell on one host cannot replace another host's data.
      path = "${dotDir}/history${lib.optionalString config.johnw.host.isSharedWork "-\${HOST%%.*}"}";
      ignoreDups = true;
      # Persist completed commands below without importing other live shells.
      share = false;
      append = true;
      extended = true;
    };

    setOptions =
      lib.optionals (!config.johnw.host.isSharedWork) [ "INC_APPEND_HISTORY_TIME" ]
      ++ lib.optionals config.johnw.host.isSharedWork [
        "INC_APPEND_HISTORY"
        "NO_INC_APPEND_HISTORY_TIME"
        "HIST_SAVE_BY_COPY"
      ];
    sessionVariables = {
      ALTERNATE_EDITOR = "${pkgs.vim}/bin/vi";
      LC_CTYPE = "en_US.UTF-8";
      LEDGER_COLOR = "true";
      LESS = "-FRSXM";
      LESSCHARSET = "utf-8";
      PAGER = "less";
      TINC_USE_NIX = "yes";
      WORDCHARS = "";
    }
    // lib.optionalAttrs isDarwin {
      ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX = "YES";
    };

    localVariables = {
      RPROMPT = if isDarwin then "%F{cyan}%f %F{green}%~%f" else "%F{green}%~%f";
      PROMPT = "%B%m %b%(!.#.$) ";
      PROMPT_DIRTRIM = "2";
    };

    shellAliases = {
      vi = "${pkgs.vim}/bin/vim";
      b = "${gitPkg}/bin/git b";
      l = "${gitPkg}/bin/git l";
      w = "${gitPkg}/bin/git w";
      ga = if config.johnw.profile.heavy then "${pkgs.git-annex}/bin/git-annex" else "git annex";
      good = "${gitPkg}/bin/git bisect good";
      bad = "${gitPkg}/bin/git bisect bad";
      par = "${pkgs.parallel}/bin/parallel";
      rX = "${pkgs.coreutils}/bin/chmod -R ugo+rX";
      scp = "${pkgs.rsync}/bin/rsync -aP --inplace";

      cb = "cabal build";
      cn = "cabal configure --enable-tests --enable-benchmarks";
      cnp =
        "cabal configure --enable-tests --enable-benchmarks "
        + "--enable-profiling --ghc-options=-fprof-auto";

      rehash = "hash -r";
    }
    // lib.optionalAttrs isDarwin {
      proc = "${pkgs.darwin.ps}/bin/ps axwwww | ${pkgs.gnugrep}/bin/grep -i";
      nstat =
        "${pkgs.darwin.network_cmds}/bin/netstat -nr -f inet"
        + " | ${pkgs.gnugrep}/bin/egrep -v \"(lo0|vmnet|169\\.254|255\\.255)\""
        + " | ${pkgs.coreutils}/bin/tail -n +5";
      wipe = "${pkgs.srm}/bin/srm -vfr";
    }
    // lib.optionalAttrs isLinux {
      proc = "ps axwwww | grep -i";
    };

    # Preserve zsh's native remote-path completion for these commands by
    # excluding them before the carapace bridge loads.
    envExtra =
      scriptsFirst
      + ''
        export CARAPACE_EXCLUDES=ssh,scp,sftp,rsync
      ''
      + lib.optionalString isLinux ''
        if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
          . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        elif [[ -f ~/.nix-profile/etc/profile.d/nix.sh ]]; then
          . ~/.nix-profile/etc/profile.d/nix.sh
        fi
      '';

    profileExtra =
      scriptsFirst
      + ''
        setopt extended_glob
      ''
      + lib.optionalString isLinux ''
        . ${pkgs.zsh-z}/share/zsh-z/zsh-z.plugin.zsh
      '';

    initContent = lib.mkOrder 2000 (
      ''
        # Make sure that fzf does not override the meaning of ^T
        bindkey '^T' transpose-chars
        bindkey -e

        if [[ $TERM == dumb || $TERM == emacs || ! -o interactive ]]; then
            unsetopt zle
            unset zle_bracketed_paste
            export PROMPT='$ '
            export RPROMPT=""
            export PS1='$ '
      ''
      + lib.optionalString isDarwin ''
        else
            . ${config.xdg.configHome}/zsh/plugins/iterm2_shell_integration
            . ${config.xdg.configHome}/shellfish/shellfishrc

            ${lib.optionalString config.johnw.host.isHera ''
              # OpenClaw Completion
              [[ -f "${vars.home}/.openclaw/completions/openclaw.zsh" ]] && \
                source "${vars.home}/.openclaw/completions/openclaw.zsh"
            ''}

          # Set terminal/tmux title to current directory
          __update_terminal_title() {
            # Use both OSC 0 (icon+title) and OSC 2 (title only)
            # %~ expands to current directory with ~ substitution
            print -Pn "\e]0;%~\a"
            # Set the OSC 2 title while inside tmux.
            if [[ -n "$TMUX" ]]; then
              print -Pn "\e]2;%~\a"
            fi
          }

          autoload -Uz add-zsh-hook
          add-zsh-hook chpwd __update_terminal_title
          add-zsh-hook precmd __update_terminal_title

          # Reset terminal state before each prompt.
          __reset_broken_terminal() {
            printf '%b' '\e[0m\e(B\e)0\017\e[?5l\e7\e[0;0r\e8'
            # Reset Kitty keyboard protocol and modifyOtherKeys.
            printf '\e[>0u\e[>4;0m' 2>/dev/null
          }
          add-zsh-hook precmd __reset_broken_terminal

          # Native remote-path completion for ssh/scp/sftp/rsync is preserved
          # by keeping these commands out of carapace (see CARAPACE_EXCLUDES in
          # envExtra above); compinit then auto-registers _ssh/_rsync for them.
        fi
      ''
      + lib.optionalString isLinux ''
        else
          # Reset terminal state before each prompt.
          autoload -Uz add-zsh-hook
          __reset_broken_terminal() {
            printf '%b' '\e[0m\e(B\e)0\017\e[?5l\e7\e[0;0r\e8'
            # Reset Kitty keyboard protocol and modifyOtherKeys.
            printf '\e[>0u\e[>4;0m' 2>/dev/null
          }
          add-zsh-hook precmd __reset_broken_terminal
        fi
      ''
      + scriptsFirst
    );

    plugins = lib.optionals isDarwin [
      {
        name = "iterm2_shell_integration";
        src =
          assert itermSource.source.fetcher == "fetchurl";
          pkgs.fetchurl itermSource.source.args;
      }
    ];
  };

  # Ordinary shells trust the dump above. Rebuild it during activation, where
  # compinit can afford to audit the complete Nix-backed completion path.
  home.activation.refreshZshCompletionDump = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      (
        set -euo pipefail
        umask 077

        completion_dump=${lib.escapeShellArg "${dotDir}/.zcompdump"}
        if [[ -v DRY_RUN ]]; then
          printf 'Would refresh zsh completion dump: %s\n' "$completion_dump"
          exit 0
        fi

        ${pkgs.coreutils}/bin/rm -f -- "$completion_dump"
        if ! ZDOTDIR=${lib.escapeShellArg dotDir} TERM=dumb \
          ${pkgs.zsh}/bin/zsh -ic exit </dev/null
        then
          echo "zsh completion audit failed" >&2
          exit 1
        fi

        expected_metadata="$(${pkgs.coreutils}/bin/id -u):600"
        actual_metadata="$(${pkgs.coreutils}/bin/stat -c '%u:%a' "$completion_dump")"
        if [[ -L $completion_dump || ! -f $completion_dump \
          || $actual_metadata != "$expected_metadata" ]]
        then
          echo "zsh completion dump has unsafe ownership or mode" >&2
          exit 1
        fi
      )
    ''
  );
}
