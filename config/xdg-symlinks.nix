{
  pkgs,
  lib,
  config,
  hostname,
  vars,
  ...
}:
let
  inherit (vars) home isDarwin isLinux;

  mkLink = config.lib.file.mkOutOfStoreSymlink;
in
{
  home.file =
    lib.optionalAttrs isDarwin {
      ".aider".source = mkLink "${config.xdg.configHome}/aider";
      ".codex".source = mkLink "${config.xdg.configHome}/codex";
      ".cups".source = mkLink "${config.xdg.configHome}/cups";
      ".cursor".source = mkLink "${config.xdg.configHome}/cursor";
      ".dbvis".source = mkLink "${config.xdg.configHome}/dbvis";
      ".factory".source = mkLink "${config.xdg.configHome}/factory";
      ".gemini".source = mkLink "${config.xdg.configHome}/gemini";
      ".gist".source = mkLink "${config.xdg.configHome}/gist/api_key";
      ".gnupg".source = mkLink "${config.xdg.configHome}/gnupg";
      ".jq".source = mkLink "${config.xdg.configHome}/jq/config";
      ".jupyter".source = mkLink "${config.xdg.configHome}/jupyter";
      ".kube".source = mkLink "${config.xdg.configHome}/kube";
      ".mitmproxy".source = mkLink "${config.xdg.configHome}/mitmproxy";
      ".parallel".source = mkLink "${config.xdg.configHome}/parallel";
      ".sage".source = mkLink "${config.xdg.configHome}/sage";

      ".diffusionbee".source = mkLink "${config.xdg.dataHome}/diffusionbee";
      ".docker".source = mkLink "${config.xdg.dataHome}/docker";
      ".vscode".source = mkLink "${config.xdg.dataHome}/vscode";
      ".w3m".source = mkLink "${config.xdg.dataHome}/w3m";
      ".wget-hsts".source = mkLink "${config.xdg.dataHome}/wget/hsts";

      ".bun".source = mkLink "${config.xdg.cacheHome}/bun";
      ".cargo".source = mkLink "${config.xdg.cacheHome}/cargo";
      ".rustup".source = mkLink "${config.xdg.cacheHome}/rustup";
      ".npm".source = mkLink "${config.xdg.cacheHome}/npm";
      ".ollama".source = mkLink "${config.xdg.cacheHome}/ollama";
      ".swiftpm".source = mkLink "${config.xdg.cacheHome}/swiftpm";
      ".thinkorswim".source = mkLink "${config.xdg.cacheHome}/thinkorswim";

      ".emacs.d".source = mkLink "${home}/src/dot-emacs";
      "dl".source = mkLink "${home}/Downloads";
      "db".source = mkLink "${home}/Databases";
      "Recordings".source =
        mkLink "${home}/Library/Mobile Documents/iCloud~com~openplanetsoftware~just-press-record/Documents";

      "pos".source = mkLink "${home}/work/positron";
      "tron".source = mkLink "${home}/work/positron/tron";
      "srp".source = mkLink "${home}/work/regional-statistics/srp-db";
      "git-ai".source = mkLink "${home}/work/git-ai/git-ai";

      "News".source = mkLink "${config.xdg.dataHome}/gnus/News";
    }
    // lib.optionalAttrs (isDarwin && hostname == "hera") {
      "Archives".source = mkLink "/Volumes/ext/Archives";
      "Audio".source = mkLink "/Volumes/ext/Audio";
      "Photos".source = mkLink "/Volumes/ext/Photos";
    }
    // lib.optionalAttrs (isDarwin && (hostname == "hera" || hostname == "clio")) {
      "org".source = mkLink "${home}/doc/org";

      "Mobile".source = mkLink "${home}/Library/Mobile Documents/com~apple~CloudDocs/Plain Org";
      "Drafts".source =
        mkLink "${home}/Library/Mobile Documents/iCloud~com~agiletortoise~Drafts5/Documents";
      "Inbox".source = mkLink "${home}/Library/Application Support/DEVONthink/Inbox";
      "iCloud".source = mkLink "${home}/Library/Mobile Documents/com~apple~CloudDocs";
    }
    // lib.optionalAttrs isLinux {
      # Factory CLI (droid) expects ripgrep at this location
      ".factory/bin/rg".source = "${pkgs.ripgrep}/bin/rg";
    };
}
