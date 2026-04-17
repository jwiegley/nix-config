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

  inherit (vars)
    gitPkg
    userName
    userEmail
    signing_key
    ca-bundle_crt
    ;

  # Generate mergiraf attributes from a list (Finding 2)
  mergirafExts = [
    "java"
    "properties"
    "kt"
    "rs"
    "go"
    "ini"
    "js"
    "jsx"
    "mjs"
    "json"
    "yml"
    "yaml"
    "toml"
    "html"
    "htm"
    "xhtml"
    "xml"
    "c"
    "h"
    "cc"
    "hh"
    "cpp"
    "hpp"
    "cxx"
    "hxx"
    "cs"
    "dart"
    "dts"
    "scala"
    "sbt"
    "ts"
    "tsx"
    "py"
    "php"
    "sol"
    "lua"
    "rb"
    "ex"
    "exs"
    "nix"
    "sv"
    "svh"
    "md"
    "hcl"
    "tf"
    "tfvars"
    "ml"
    "mli"
    "hs"
    "mk"
    "bzl"
    "bazel"
    "cmake"
  ];
  mergirafFiles = [
    "go.mod"
    "go.sum"
    "go.work.sum"
    "pyproject.toml"
    "Makefile"
    "GNUmakefile"
    "BUILD"
    "WORKSPACE"
    "CMakeLists.txt"
  ];
in
{
  programs.git = {
    enable = true;
    package = gitPkg;

    signing = lib.mkDefault {
      format = "openpgp";
      key = signing_key;
      signByDefault = true;
    };

    includes = [
      { path = "~/.config/git/persona.gitconfig"; }
    ];

    settings = {
      alias = {
        amend = "commit --amend -C HEAD";
        authors =
          ''!"${gitPkg}/bin/git log --pretty=format:%aN''
          + " | ${pkgs.coreutils}/bin/sort"
          + " | ${pkgs.coreutils}/bin/uniq -c"
          + " | ${pkgs.coreutils}/bin/sort -rn\"";
        b = "branch --color -v";
        ca = "commit --amend";
        changes = "diff --name-status -r";
        clone = "clone --recursive";
        co = "checkout";
        cp = "cherry-pick";
        dc = "diff --cached";
        dh = "diff HEAD";
        ds = "diff --staged";
        from = "!${gitPkg}/bin/git bisect start && ${gitPkg}/bin/git bisect bad HEAD && ${gitPkg}/bin/git bisect good";
        ls-ignored = "ls-files --exclude-standard --ignored --others";
        rc = "rebase --continue";
        rh = "reset --hard";
        ri = "rebase --interactive";
        rs = "rebase --skip";
        ru = "remote update --prune";
        snap = "!${gitPkg}/bin/git stash" + " && ${gitPkg}/bin/git stash apply";
        snaplog =
          "!${gitPkg}/bin/git log refs/snapshots/refs/heads/" + "$(${gitPkg}/bin/git rev-parse HEAD)";
        spull =
          "!${gitPkg}/bin/git stash" + " && ${gitPkg}/bin/git pull" + " && ${gitPkg}/bin/git stash pop";
        su = "submodule update --init --recursive";
        unstage = "reset --soft HEAD^";
        w = "status -sb";
        wr = "worktree remove";
        wdiff = "diff --color-words";
        l =
          "log --graph --pretty=format:'%Cred%h%Creset"
          + " —%Cblue%d%Creset %s %Cgreen(%cr)%Creset'"
          + " --abbrev-commit --date=relative --show-notes=*";
      };

      user = {
        name = userName;
        email = userEmail;
      };

      core = {
        editor = lib.mkDefault vars.emacsclient;
        trustctime = false;
        pager = "${pkgs.less}/bin/less --tabs=4 -RFX";
        logAllRefUpdates = true;
        precomposeunicode = false;
        whitespace = "trailing-space,space-before-tab";
      };

      branch.autosetupmerge = true;
      commit.gpgsign = lib.mkDefault true;
      commit.status = false;
      github.user = "jwiegley";
      credential.helper = lib.mkDefault "${pkgs.pass-git-helper}/bin/pass-git-helper";
      hub.protocol = "${pkgs.openssh}/bin/ssh";
      mergetool.keepBackup = true;
      pull.rebase = true;
      rebase.autosquash = true;
      rebase.autoStash = true;
      rerere.enabled = true;
      rerere.autoupdate = true;
      init.defaultBranch = "main";

      "merge \"ours\"".driver = true;
      "magithub \"ci\"".enabled = false;

      http = {
        sslCAinfo = ca-bundle_crt;
        sslverify = true;
      };

      color = {
        status = "auto";
        diff = "auto";
        branch = "auto";
        interactive = "auto";
        ui = "auto";
        sh = "auto";
      };

      push = {
        autoSetupRemote = true;
        default = "simple";
      };

      "merge \"mergiraf\"" = {
        name = "mergiraf";
        driver = "${pkgs.mergiraf}/bin/mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L";
      };

      merge = {
        conflictstyle = "diff3";
        stat = true;
      };

      "color \"sh\"" = {
        branch = "yellow reverse";
        workdir = "blue bold";
        dirty = "red";
        dirty-stash = "red";
        repo-state = "red";
      };

      annex = {
        backends = "BLAKE2B512E";
        alwayscommit = false;
      };

      "filter \"media\"" = {
        required = true;
        clean = "${gitPkg}/bin/git media clean %f";
        smudge = "${gitPkg}/bin/git media smudge %f";
      };

      diff = {
        ignoreSubmodules = "dirty";
        renames = "copies";
        mnemonicprefix = true;
      };

      advice = {
        statusHints = false;
        pushNonFastForward = false;
        objectNameWarning = "false";
      };

      "filter \"lfs\"" = {
        clean = "git-lfs clean -- %f";
        smudge = "git-lfs smudge --skip -- %f";
        required = true;
      };

      "url \"git://github.com/ghc/packages-\"".insteadOf = "git://github.com/ghc/packages/";
      "url \"http://github.com/ghc/packages-\"".insteadOf = "http://github.com/ghc/packages/";
      "url \"https://github.com/ghc/packages-\"".insteadOf = "https://github.com/ghc/packages/";
      "url \"ssh://git@github.com/ghc/packages-\"".insteadOf = "ssh://git@github.com/ghc/packages/";
      "url \"git@github.com:/ghc/packages-\"".insteadOf = "git@github.com:/ghc/packages/";
    }
    // lib.optionalAttrs (pkgs ? git-scripts) {
      "merge \"merge-changelog\"" = {
        name = "GNU-style ChangeLog merge driver";
        driver = "${pkgs.git-scripts}/bin/git-merge-changelog %O %A %B";
      };
    };

    ignores = [
      "#*#"
      "*.a"
      "*.agdai"
      "*.aux"
      "*.dylib"
      "*.elc"
      "*.glob"
      "*.hi"
      "*.la"
      "*.lia.cache"
      "*.lra.cache"
      "*.nia.cache"
      "*.nra.cache"
      "*.o"
      "*.so"
      "*.v.d"
      "*.v.tex"
      "*.vio"
      "*.vo"
      "*.vok"
      "*.vos"
      "*~"
      ".*.aux"
      ".DS_Store"
      ".localized"
      ".Makefile.d"
      ".clean"
      ".coq-native/"
      ".coqdeps.d"
      ".direnv/"
      ".envrc"
      ".envrc.cache"
      ".envrc.override"
      ".ghc.environment.x86_64-darwin-*"
      ".ghc.environment.x86_64-linux-*"
      ".makefile"
      ".pact-history"
      "TAGS"
      "cabal.project.local*"
      "settings.local.json"
      ".taskmaster"
      "prd.txt"
      "prd.md"
      "default.hoo"
      "default.warn"
      "dist-newstyle/"
      "ghc[0-9]*_[0-9]*/"
      "input-haskell-*.tar.gz"
      "input-haskell-*.txt"
      "result"
      "result-*"
      "tags"
    ];

    attributes =
      (map (ext: "*.${ext} merge=mergiraf") mergirafExts)
      ++ (map (f: "${f} merge=mergiraf") mergirafFiles);
  };
}
