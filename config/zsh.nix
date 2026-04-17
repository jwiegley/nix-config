{
  pkgs,
  lib,
  config,
  hostname,
  inputs,
  ...
}:
let
  vars = import ./vars.nix {
    inherit
      pkgs
      lib
      config
      hostname
      inputs
      ;
  };

  inherit (vars) isDarwin isLinux gitPkg;

  dotDir = "${config.xdg.configHome}/zsh";
in
{
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

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 500000;
      path = "${config.xdg.configHome}/zsh/history";
      ignoreDups = true;
      share = true;
      append = true;
      extended = true;
    };

    sessionVariables = {
      ALTERNATE_EDITOR = "${pkgs.vim}/bin/vi";
      LC_CTYPE = "en_US.UTF-8";
      LEDGER_COLOR = "true";
      LESS = "-FRSXM";
      LESSCHARSET = "utf-8";
      PAGER = "less";
      TINC_USE_NIX = "yes";
      WORDCHARS = "";

      ZSH_THEME_GIT_PROMPT_CACHE = "yes";
      ZSH_THEME_GIT_PROMPT_CHANGED = "%{$fg[yellow]%}%{✚%G%}";
      ZSH_THEME_GIT_PROMPT_STASHED = "%{$fg_bold[yellow]%}%{⚑%G%}";
      ZSH_THEME_GIT_PROMPT_UPSTREAM_FRONT = " {%{$fg[yellow]%}";
    }
    // lib.optionalAttrs isDarwin {
      ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX = "YES";
    };

    localVariables = {
      RPROMPT = if isDarwin then "%F{cyan}[\\$PERSONA]%f %F{green}%~%f" else "%F{green}%~%f";
      PROMPT = "%B%m %b\\$(git_super_status)%(!.#.$) ";
      PROMPT_DIRTRIM = "2";
    };

    shellAliases = {
      vi = "${pkgs.vim}/bin/vim";
      b = "${gitPkg}/bin/git b";
      l = "${gitPkg}/bin/git l";
      w = "${gitPkg}/bin/git w";
      ga = "${pkgs.git-annex}/bin/git-annex";
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
      switch = "${pkgs.nix-scripts}/bin/u ${hostname} switch";
      proc = "${pkgs.darwin.ps}/bin/ps axwwww | ${pkgs.gnugrep}/bin/grep -i";
      nstat =
        "${pkgs.darwin.network_cmds}/bin/netstat -nr -f inet"
        + " | ${pkgs.gnugrep}/bin/egrep -v \"(lo0|vmnet|169\\.254|255\\.255)\""
        + " | ${pkgs.coreutils}/bin/tail -n +5";
      wipe = "${pkgs.srm}/bin/srm -vfr";
    }
    // lib.optionalAttrs isLinux {
      switch = "sudo nixos-rebuild switch --flake /etc/nixos#${hostname}";
      proc = "ps axwwww | grep -i";
    };

    envExtra = lib.optionalString isLinux ''
      if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      elif [[ -f ~/.nix-profile/etc/profile.d/nix.sh ]]; then
        . ~/.nix-profile/etc/profile.d/nix.sh
      fi
    '';

    profileExtra = ''
      setopt extended_glob
    ''
    + lib.optionalString isLinux ''
      . ${pkgs.zsh-z}/share/zsh-z/zsh-z.plugin.zsh
    '';

    initContent =
      let
        common-begin = [
          "# Make sure that fzf does not override the meaning of ^T"
          "bindkey '^T' transpose-chars"
          "bindkey -e"
          ""
          "if [[ $TERM == dumb || $TERM == emacs || ! -o interactive ]]; then"
          "    unsetopt zle"
          "    unset zle_bracketed_paste"
          "    export PROMPT='$ '"
          "    export RPROMPT=\"\""
          "    export PS1='$ '"
          "else"
        ];

        darwin-section = [
          "    . ${config.xdg.configHome}/zsh/plugins/iterm2_shell_integration"
          "    . ${config.xdg.configHome}/shellfish/shellfishrc"
          ""
          "    fpath=(\"${config.xdg.configHome}/zsh/completions\" $fpath)"
          ""
        ]
        ++ lib.optionals (hostname == "hera") [
          "    # OpenClaw Completion"
          "    [[ -f \"${vars.home}/.openclaw/completions/openclaw.zsh\" ]] && \\"
          "      source \"${vars.home}/.openclaw/completions/openclaw.zsh\""
        ];

        reset-terminal-common = [
          ""
          "    # Reset terminal state before each prompt to prevent"
          "    # accumulated escape sequence corruption (especially"
          "    # over SSH with tmux -CC, and after Claude Code exits)"
          "    __reset_broken_terminal() {"
          "      printf '%b' '\\e[0m\\e(B\\e)0\\017\\e[?5l\\e7\\e[0;0r\\e8'"
          "      # Reset Kitty keyboard protocol and modifyOtherKeys"
          "      # (Claude Code enables these and may not clean up on crash)"
          "      printf '\\e[>0u\\e[>4;0m' 2>/dev/null"
          "    }"
          "    autoload -Uz add-zsh-hook"
          "    add-zsh-hook precmd __reset_broken_terminal"
        ];

        darwin-after = [
          ""
          "    # Set terminal/tmux title to current directory"
          "    __update_terminal_title() {"
          "      print -Pn \"\\e]0;%~\\a\""
          "      if [[ -n \"$TMUX\" ]]; then"
          "        print -Pn \"\\e]2;%~\\a\""
          "      fi"
          "    }"
          ""
          "    # Auto-load persona environment on shell start"
          "    if [[ -f \"$HOME/.config/persona/current\" ]]; then"
          "      eval \"$(command persona --env)\""
          "    fi"
          ""
          "    autoload -Uz add-zsh-hook"
          "    add-zsh-hook chpwd __update_terminal_title"
          "    add-zsh-hook precmd __update_terminal_title"
          ""
        ]
        ++ reset-terminal-common
        ++ [
          ""
          "    # Restore native zsh completions for commands that need"
          "    # SSH-based remote path completion (overridden by carapace)"
          "    autoload -Uz _rsync && compdef _rsync rsync"
          "    autoload -Uz _ssh && compdef _ssh ssh scp sftp"
          "fi"
        ];

        linux-section = [
          "    autoload -Uz compinit"
          "    compinit"
          ""
        ]
        ++ reset-terminal-common
        ++ [
          "fi"
        ];
      in
      lib.concatStringsSep "\n" (
        common-begin
        ++ darwin-section
        ++ lib.optionals isDarwin darwin-after
        ++ lib.optionals isLinux linux-section
      );

    plugins = lib.optionals isDarwin [
      {
        name = "iterm2_shell_integration";
        src = pkgs.fetchurl {
          url = "https://iterm2.com/shell_integration/zsh";
          sha256 = "0yhfnaigim95sk1idrc3hpwii8hfhjl5m3lyc0ip3vi1a9npq0li";
        };
      }
    ];
  };
}
