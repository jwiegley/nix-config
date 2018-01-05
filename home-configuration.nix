{ pkgs, ... }:

let home_directory = builtins.getEnv "HOME"; in
rec {
  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = true;

    packageOverrides = pkgs: import ./overrides.nix { pkgs = pkgs; };
  };

  home = {
    packages = with pkgs; [
      coq84Env
      coq85Env
      coq86Env
      coq87Env
      emacs25Env
      emacs26DebugEnv
      emacs26Env
      emacs26FullEnv
      emacsHEADEnv
      ghc80Env
      ghc80ProfEnv
      ghc82Env
      ghc82ProfEnv
      ledgerPy2Env
      ledgerPy3Env
    ];

    # file = {
    #   "Library/KeyBindings/DefaultKeyBinding.dict".source
    #     = ~/src/home/Library/KeyBindings/DefaultKeyBinding.dict;
    #   "Library/Keyboard Layouts/PersianDvorak.keylayout".source
    #     = builtins.toPath("${home_directory}/src/home/Library/Keyboard Layouts/PersianDvorak.keylayout");
    #   "Library/Scripts/Applications/Download links to PDF.scpt".source
    #     = builtins.toPath("${home_directory}/src/home/Library/Scripts/Applications/Download links to PDF.scpt");
    #   "Library/Scripts/Applications/Media Pro".source
    #     = builtins.toPath("${home_directory}/src/home/Library/Scripts/Applications/Media Pro");

    file = builtins.listToAttrs (
      map (path: {
             name = path;
             value = {
               source = builtins.toPath("${home_directory}/src/home/${path}");
             };
           })
          [ "Library/KeyBindings/DefaultKeyBinding.dict"
            "Library/Keyboard Layouts/PersianDvorak.keylayout"
            "Library/Scripts/Applications/Download links to PDF.scpt"
            "Library/Scripts/Applications/Media Pro" ]
        ++
      map (path: {
             name = "." + path;
             value = {
               source = builtins.toPath("${home_directory}/src/home/dot-files/${path}");
             };
           })
          [ "Xresources"
            "gitattributes"
            "inputrc"
            "ledgerrc"
            "lftprc"
            "pushme"
            "screenrc"
            "slate"
            "tmux.conf" ]);

  };

  programs.bash = {
    enable = true;

    historySize     = 5000;
    historyFileSize = 50000;
    historyControl  = [ "ignoredups" "ignorespace" "erasedups" ];
    shellOptions    = [ "histappend" ];

    sessionVariables = {
      ASPELL_CONF        = "${xdg.configHome}/aspell/config";
      GNUPGHOME          = "${xdg.configHome}/gnupg";
      PASSWORD_STORE_DIR = "${home_directory}/doc/.passwords";

      COQVER             = "87";
      EMACSVER           = "26";
      GHCVER             = "82";
      GHCPKGVER          = "822";

      ALTERNATE_EDITOR   = "vi";
      COLUMNS            = "100";
      EDITOR             = "emacsclient -a vi";
      EMAIL              = "${programs.git.userEmail}";
      JAVA_OPTS          = "-Xverify:none";
      LC_CTYPE           = "en_US.UTF-8";
      LESS               = "-FRSXM";
      PROMPT_DIRTRIM     = "2";
      PS1                = "\\D{%H:%M} \\h:\\W $ ";
      WORDCHARS          = "";
    };

    shellAliases = {
      b   = "git branch --color -v";
      g   = "hub";
      ga  = "git-annex";
      git = "hub";
      l   = "git l";
      ls  = "ls --color=auto";
      par = "parallel";
      rm  = "rmtrash";
      scp = "rsync -aP --inplace";
      w   = "git status -sb";
    };

    initExtra = ''
      for file in \
          ${xdg.configHome}/fetchmail \
          ${xdg.configHome}/fetchmail-lists
      do
          cp -pL $file ''${file}.copy
          chmod 0600 ''${file}.copy
      done

      if [[ -x "$(which docker-machine)" ]]; then
          if docker-machine status default > /dev/null 2>&1; then
              eval $(docker-machine env default) > /dev/null 2>&1
          fi
      fi

      export GPG_TTY=$(${pkgs.coreutils}/bin/tty)
      if [[ -f ~/.gpg-agent-info ]]; then
          . ~/.gpg-agent-info
          export GPG_AGENT_INFO
          export SSH_AUTH_SOCK
          export SSH_AGENT_PID
      fi

      export PATH=$HOME/bin:$PATH

      ln -sf Contracts/BAE/Projects ~/bae
      ln -sf Contracts/OSS/Projects ~/oss
      ln -sf Documents ~/doc
      ln -sf Downloads ~/dl
      ln -sf Projects ~/src
      ln -sf Projects/dot-emacs ~/emacs
      ln -sf Projects/scripts ~/bin
    '';
  };

  programs.git = {
    enable = true;

    userName = "John Wiegley";
    userEmail = "johnw@newartisans.com";

    signing = {
      key = "C144D8F4F19FE630";
      signByDefault = false;
    };

    aliases = {
    	amend      = "commit --amend -C HEAD";
    	authors    = "!\"git log --pretty=format:%aN | sort | uniq -c | sort -rn\"";
    	b          = "branch -v";
    	c          = "commit";
    	ca         = "commit --amend";
    	changes    = "diff --name-status -r";
    	ci         = "commit";
    	cl         = "clone --recursive";
    	cm         = "checkout master";
    	co         = "checkout";
    	cp         = "cherry-pick";
    	dc         = "diff --cached";
    	ds         = "diff --staged";
    	ls-ignored = "ls-files --exclude-standard --ignored --others";
    	m          = "merge";
    	mm         = "merge --no-ff";
    	msg        = "commit --allow-empty -m";
    	p          = "cherry-pick -s";
    	pick       = "cherry-pick";
    	pull       = "pull --ff";
    	r          = "remote";
    	rc         = "rebase --continue";
    	rh         = "reset --hard";
    	ri         = "rebase -i";
    	rs         = "rebase --skip";
    	ru         = "remote update --prune";
    	sh         = "!git-sh";
    	snap       = "!git stash && git stash apply";
    	sp         = "!\"git stash ; git pull ; git stash pop\"";
    	spull      = "!git stash && git pull && git stash pop";
    	st         = "stash";
    	stl        = "stash list";
    	stp        = "stash pop";
    	su         = "submodule update --init";
    	undo       = "reset --soft HEAD^";
    	w          = "git status";
    	wd         = "diff --color-words";
      l          = "log --graph --pretty=format:'%Cred%h%Creset —%Cblue%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative --show-notes=*";
    };

    extraConfig = {
      core = {
      	editor            = "emacsclient";
      	trustctime        = false;
      	fsyncobjectfiles  = true;
      	pager             = "less --tabs=4 -RFX";
      	logAllRefUpdates  = true;
      	precomposeunicode = false;
      	whitespace        = "trailing-space,space-before-tab";
      };

      branch.autosetupmerge = true;
      commit.gpgsign = false;
      credential.helper = "osxkeychain";
      ghi.token = "!security find-internet-password -a jwiegley -s github.com -l 'ghi token' -w";
      hub.protocol = "https";
      mergetool.keepBackup = true;
      pull.rebase = true;
      rebase.autosquash = true;
      rerere.enabled = true;

      "merge \"ours\"".driver = true;
      "magithub \"ci\"".enabled = false;

      http = {
        sslCAinfo = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        sslverify = true;
      };

      color = {
       	status      = "auto";
       	diff        = "auto";
       	branch      = "auto";
       	interactive = "auto";
       	ui          = "auto";
       	sh          = "auto";
      };

      push = {
      	default = "tracking";
      	recurseSubmodules = "check";
      };

      "merge \"merge-changelog\"" = {
      	name = "GNU-style ChangeLog merge driver";
      	driver = "git-merge-changelog %O %A %B";
      };

      merge = {
      	conflictstyle = "diff3";
      	stat = true;
      };

      "color \"sh\"" = {
      	branch      = "yellow reverse";
      	workdir     = "blue bold";
      	dirty       = "red";
      	dirty-stash = "red";
      	repo-state  = "red";
      };

      annex = {
      	backends = "SHA512E";
      	alwayscommit = false;
      };

      "filter \"media\"" = {
      	required = true;
      	clean = "git media clean %f";
      	smudge = "git media smudge %f";
      };

      diff = {
      	ignoreSubmodules = "dirty";
      	renames = "copies";
      	mnemonicprefix = true;
      };

      advice = {
      	statusHints = false;
      	pushNonFastForward = false;
      };

      "filter \"lfs\"" = {
      	clean    = "git-lfs clean -- %f";
      	smudge   = "git-lfs smudge --skip -- %f";
      	required = true;
      };

      "url \"git://github.com/ghc/packages-\"".insteadOf
        = "git://github.com/ghc/packages/";
      "url \"http://github.com/ghc/packages-\"".insteadOf
        = "http://github.com/ghc/packages/";
      "url \"https://github.com/ghc/packages-\"".insteadOf
        = "https://github.com/ghc/packages/";
      "url \"ssh://git\\@github.com/ghc/packages-\"".insteadOf
        = "ssh://git@github.com/ghc/packages/";
      "url \"git\\@github.com:/ghc/packages-\"".insteadOf
        = "git@github.com:/ghc/packages/";
    };

    ignores = [
      "*.elc"
    ];
  };

  xdg = {
    enable = true;

    configHome = "${home_directory}/.config";

    configFile."gnupg/gpg-agent.conf".text = ''
      enable-ssh-support
      default-cache-ttl 600
      max-cache-ttl 7200
      pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
      scdaemon-program ${xdg.configHome}/gnupg/scdaemon-wrapper
    '';

    configFile."gnupg/scdaemon-wrapper" = {
      text = ''
        #!/bin/bash
        export DYLD_FRAMEWORK_PATH=/System/Library/Frameworks
        exec ${pkgs.gnupg}/libexec/scdaemon "$@"
      '';
      executable = true;
    };

    configFile."aspell/config".text = ''
      data-dir ${pkgs.aspell}/lib/aspell
      personal ${xdg.configHome}/aspell/en.personal
      repl ${xdg.configHome}/aspell/en.repl
    '';

    configFile."msmtp".text = ''
      defaults

      tls on
      tls_starttls on
      tls_trust_file ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

      account fastmail
      host smtp.fastmail.com
      port 587
      auth on
      user ${programs.git.userEmail}
      passwordeval pass smtp.fastmail.com
      from ${programs.git.userEmail}
      logfile ${home_directory}/Library/Logs/msmtp.log
    '';

    configFile."fetchmail".text = ''
      poll imap.fastmail.com protocol IMAP port 993
        user '${programs.git.userEmail}' there is johnw here
        ssl sslcertck sslcertfile "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        folder INBOX
        fetchall
        mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -e"
    '';

    configFile."fetchmail-lists".text = ''
      poll imap.fastmail.com protocol IMAP port 993
        user '${programs.git.userEmail}' there is johnw here
        ssl sslcertck sslcertfile "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        folder 'Lists'
        fetchall
        mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -e -m list.misc"
    '';
  };

  programs.browserpass = {
    enable = true;
    browsers = [ "firefox" ];
  };

  programs.home-manager = {
    enable = true;
    path = "~/oss/home-manager";
  };
}
