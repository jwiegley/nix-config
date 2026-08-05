{
  darwinConfigurations,
  homeConfigurations,
  nixosHomeEvaluationFixtures,
  pkgs,
}:

let
  inherit (pkgs) lib;
  registry = import ../../config/hosts/registry.nix;
  catalog = import ../../config/ai/catalog.nix {
    inherit lib;
    resources = "/catalog-agent-resources";
  };
  desktopPackages = [
    "eask-cli"
    "emacs-lsp-booster"
    "env-emacs30MacPort"
    "git-crypt"
    "git-secret"
    "gnupg"
    "paperkey"
    "pass-env"
    "pass-git-helper"
  ];
  desktopVariables = [
    "EDITOR"
    "EMACS_SERVER_FILE"
    "EMACSVER"
    "RCLONE_PASSWORD_COMMAND"
    "RESTIC_PASSWORD_COMMAND"
    "SSH_AUTH_SOCK"
  ];
  desktopSigningKey = registry.hosts.hera.signingKey;
  positive = map (host: darwinConfigurations.${host}.config.home-manager.users.johnw) [
    "hera"
    "clio"
  ];
  vpsHome = nixosHomeEvaluationFixtures.vps.config;
  negative = [
    nixosHomeEvaluationFixtures.vulcan.config
    vpsHome
    homeConfigurations."jwiegley@x86_64-linux".config
    homeConfigurations."johnw@aarch64-linux".config
  ];
  sharedWork = homeConfigurations."jwiegley@x86_64-linux".config;
  allHomes = positive ++ negative;
  piHomes = allHomes;
  blackholeActivations = map (config: config.home.activation.aiManagedPiBlackholePolicy) piHomes;
  blackholeActivation =
    if pkgs.stdenv.hostPlatform.isDarwin then
      builtins.head blackholeActivations
    else if pkgs.stdenv.hostPlatform.system == "aarch64-linux" then
      nixosHomeEvaluationFixtures.vulcan.config.home.activation.aiManagedPiBlackholePolicy
    else
      sharedWork.home.activation.aiManagedPiBlackholePolicy;
  piExtensionPaths = map (name: ".config/pi/agent/extensions/${name}") [
    "fleet-theme/index.ts"
    "nix-gallery/index.ts"
    "pi-loop/index.ts"
    "pi-mcp-adapter"
    "pi-quiet"
  ];
  vpsPiSkills = catalog.select catalog.profiles.vps-pi catalog.items.skills;
  vpsPiSkillNames = builtins.attrNames vpsPiSkills;
  modelProviderNames =
    config:
    builtins.attrNames
      (builtins.fromJSON (builtins.readFile config.home.file.".config/pi/agent/models.json".source))
      .providers;
  packageNamesFor = config: map lib.getName config.home.packages;
  contains = needle: value: builtins.isString value && lib.hasInfix needle value;
  featureFlags =
    config:
    let
      packageNames = packageNamesFor config;
      variables = config.home.sessionVariables or { };
      files = config.home.file or { };
      git = config.programs.git;
      gitSettings = git.settings or { };
      emailAccounts = builtins.attrValues (config.accounts.email.accounts or { });
      emailPasswordCommands = map (account: account.passwordCommand or "") emailAccounts;
      runtimeOptions = builtins.toJSON {
        inherit emailPasswordCommands variables;
        git = gitSettings;
        gh = config.programs.gh.settings or { };
      };
      runtimeText = builtins.unsafeDiscardStringContext runtimeOptions;
      runtimeReferences = map lib.getName (builtins.attrNames (builtins.getContext runtimeOptions));
      runtimeNameForbidden =
        name:
        builtins.any (root: name == root || lib.hasPrefix "${root}-" name) [
          "emacs"
          "gnupg"
          "pass"
          "password-store"
        ];
    in
    map (name: builtins.elem name packageNames) desktopPackages
    ++ map (name: builtins.hasAttr name variables) desktopVariables
    ++ map (name: builtins.hasAttr name files) [
      ".emacs.d"
      ".gnupg"
    ]
    ++ [
      (config.programs.browserpass.enable or false)
      (config.programs.gpg.enable or false)
      (config.programs.password-store.enable or false)
      (config.services.gpg-agent.enable or false)
      (emailAccounts != [ ])
      (builtins.any (account: (account.gpg.key or null) == desktopSigningKey) emailAccounts)
      ((git.signing.format or null) == "openpgp")
      ((git.signing.key or null) == desktopSigningKey)
      ((git.signing.signByDefault or false) == true)
      ((lib.attrByPath [ "commit" "gpgsign" ] false gitSettings) == true)
      (contains "pass-git-helper" (lib.attrByPath [ "credential" "helper" ] "" gitSettings))
      (contains "emacs" (variables.EDITOR or ""))
      (contains "emacs" (lib.attrByPath [ "core" "editor" ] "" gitSettings))
      (contains "emacs" (config.programs.gh.settings.editor or ""))
      (
        contains "/bin/pass" runtimeText
        || contains "emacs" runtimeText
        || builtins.any runtimeNameForbidden runtimeReferences
      )
    ];
  allTrue = values: builtins.all lib.id values;
  allFalse = values: builtins.all (value: !value) values;
  desktopRegistry = map (host: registry.hosts.${host}) [
    "hera"
    "clio"
  ];
  serverRegistry = map (host: registry.hosts.${host}) [
    "vulcan"
    "vps"
    "andoria"
  ];
in
assert builtins.all (host: host.signing == "openpgp" && host.signingKey != null) desktopRegistry;
assert registry.hosts.clio.signingKey == desktopSigningKey;
assert builtins.all (host: host.signing == "none" && host.signingKey == null) serverRegistry;
assert builtins.all (config: config.johnw.host.isDarwinWorkstation) positive;
assert builtins.all (config: !config.johnw.host.isDarwinWorkstation) negative;
assert
  sharedWork.programs.zsh.history.path == "${sharedWork.xdg.configHome}/zsh/history-\${HOST%%.*}";
assert !sharedWork.programs.zsh.history.share;
assert builtins.elem "INC_APPEND_HISTORY" sharedWork.programs.zsh.setOptions;
assert builtins.all (config: builtins.hasAttr ".pi" config.home.file) piHomes;
assert builtins.all (
  config: builtins.hasAttr ".config/pi/agent/models.json" config.home.file
) piHomes;
assert builtins.all (
  activation: activation.before == [ ] && activation.after == [ "linkGeneration" ]
) blackholeActivations;
assert builtins.all (
  config:
  builtins.all (name: !(builtins.hasAttr name (config.home.sessionVariables or { }))) [
    "PI_BLACKHOLE_PASSIVE"
    "PI_BLACKHOLE_COMPACTION"
    "PI_BLACKHOLE_COMPACTION_ENGINE"
    "PI_VCC_OM_PASSIVE"
    "PI_OBSERVATIONAL_MEMORY_PASSIVE"
  ]
) piHomes;
assert builtins.all (
  config: builtins.hasAttr ".config/pi/agent/model-router.json" config.home.file
) positive;
assert builtins.all (
  config: !(builtins.hasAttr ".config/pi/agent/model-router.json" config.home.file)
) negative;
assert builtins.all (
  config:
  modelProviderNames config == [
    "llama-swap"
    "omlx"
    "openai-codex"
    "openrouter"
    "router"
  ]
) positive;
assert builtins.all (
  config:
  modelProviderNames config == [
    "openai-codex"
    "openrouter"
  ]
) negative;
assert builtins.all (
  config: builtins.all (path: builtins.hasAttr path config.home.file) piExtensionPaths
) piHomes;
assert builtins.all (
  config:
  !(builtins.hasAttr ".config/pi/agent/extensions/auto-compact-resume/index.ts" config.home.file)
) piHomes;
assert builtins.all (
  name:
  let
    path = ".agents/skills/${name}";
    expectedSuffix = lib.removePrefix "/catalog-agent-resources/" (toString vpsPiSkills.${name}.source);
  in
  builtins.hasAttr path vpsHome.home.file
  && lib.hasSuffix expectedSuffix (toString vpsHome.home.file.${path}.source)
) vpsPiSkillNames;
assert builtins.all (config: builtins.elem "unisessions" (packageNamesFor config)) allHomes;
assert builtins.all (config: allTrue (featureFlags config)) positive;
assert builtins.all (config: allFalse (featureFlags config)) negative;
assert builtins.all (
  config: !(lib.hasAttrByPath [ "gpg" "openpgp" "program" ] (config.programs.git.settings or { }))
) negative;
assert builtins.all
  (
    host:
    darwinConfigurations.${host}.config.programs.gnupg.agent.enable
    && lib.hasAttrByPath [ "launchd" "user" "agents" "gnupg-agent" ] darwinConfigurations.${host}.config
  )
  [
    "hera"
    "clio"
  ];
pkgs.runCommand "desktop-only-user-runtime" { } ''
  export HOME="$TMPDIR/home"
  config_dir="$HOME/.config/pi/agent/pi-blackhole"
  config_path="$config_dir/pi-blackhole-config.json"

  export DRY_RUN=1
  ${blackholeActivation.data}
  [ ! -e "$config_dir" ]
  unset DRY_RUN

  ${blackholeActivation.data}
  ${pkgs.jq}/bin/jq -e '
    . == {
      compaction: "auto",
      compactionEngine: "blackhole",
      memory: true,
      midRunCompaction: "resume"
    }
  ' "$config_path" >/dev/null
  [ "$(${pkgs.coreutils}/bin/stat -c %a "$config_dir")" = 700 ]
  [ "$(${pkgs.coreutils}/bin/stat -c %a "$config_path")" = 600 ]

  ${pkgs.jq}/bin/jq '. + {
    compactionEngine: "pi-default",
    memory: false,
    midRunCompaction: "off",
    noAutoCompact: true,
    passive: true,
    overrideDefaultCompaction: false,
    compactAfterTokens: 123456,
    model: { provider: "openai-codex", id: "fixture" }
  }' "$config_path" > "$config_path.stale"
  ${pkgs.coreutils}/bin/mv "$config_path.stale" "$config_path"
  ${blackholeActivation.data}
  ${pkgs.jq}/bin/jq -e '
    .memory == true
    and .compaction == "auto"
    and .compactionEngine == "blackhole"
    and .midRunCompaction == "resume"
    and .compactAfterTokens == 123456
    and .model == { provider: "openai-codex", id: "fixture" }
    and (has("noAutoCompact") | not)
    and (has("passive") | not)
    and (has("overrideDefaultCompaction") | not)
  ' "$config_path" >/dev/null

  ${pkgs.coreutils}/bin/chmod 0644 "$config_path"
  inode_before="$(${pkgs.coreutils}/bin/stat -c %i "$config_path")"
  ${blackholeActivation.data}
  inode_after="$(${pkgs.coreutils}/bin/stat -c %i "$config_path")"
  [ "$inode_before" = "$inode_after" ]
  [ "$(${pkgs.coreutils}/bin/stat -c %a "$config_path")" = 600 ]

  printf '%s\n' '{invalid' > "$config_path.invalid"
  ${pkgs.coreutils}/bin/mv "$config_path.invalid" "$config_path"
  if ${blackholeActivation.data}
  then
    echo "Blackhole policy accepted invalid JSON" >&2
    exit 1
  fi
  [ "$(cat "$config_path")" = '{invalid' ]

  export HOME="$TMPDIR/symlink-home"
  config_dir="$HOME/.config/pi/agent/pi-blackhole"
  ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/pi/agent"
  ${pkgs.coreutils}/bin/mkdir -p "$HOME/redirected-blackhole"
  ${pkgs.coreutils}/bin/ln -s "$HOME/redirected-blackhole" "$config_dir"
  if ${blackholeActivation.data}
  then
    echo "Blackhole policy followed a redirected configuration directory" >&2
    exit 1
  fi
  [ -z "$(${pkgs.findutils}/bin/find "$HOME/redirected-blackhole" -mindepth 1 -print -quit)" ]

  export HOME="$TMPDIR/config-symlink-home"
  config_dir="$HOME/.config/pi/agent/pi-blackhole"
  config_path="$config_dir/pi-blackhole-config.json"
  sentinel="$HOME/blackhole-sentinel.json"
  ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
  printf '%s\n' '{"sentinel":true}' > "$sentinel"
  ${pkgs.coreutils}/bin/ln -s "$sentinel" "$config_path"
  if ${blackholeActivation.data}
  then
    echo "Blackhole policy followed a redirected configuration file" >&2
    exit 1
  fi
  [ -L "$config_path" ]
  [ "$(cat "$sentinel")" = '{"sentinel":true}' ]

  touch "$out"
''
