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

  inherit (vars) home isDarwin;
in
{
  home.file = lib.mkIf (isDarwin && hostname == "hera") {
    "Library/LaunchAgents/com.newartisans.cleanup.plist" = {
      text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.newartisans.cleanup</string>
          <key>EnvironmentVariables</key>
          <dict>
            <key>PYTHONPATH</key>
            <string>${pkgs.dirscan}/${pkgs.python3.sitePackages}</string>
          </dict>
          <key>ProgramArguments</key>
          <array>
            <string>/usr/bin/python3</string>
            <string>${pkgs.dirscan}/bin/.cleanup-wrapped</string>
            <string>-u</string>
          </array>
          <key>StartInterval</key>
          <integer>86400</integer>
          <key>RunAtLoad</key>
          <false/>
          <key>StandardOutPath</key>
          <string>${home}/Library/Logs/cleanup.stdout.log</string>
          <key>StandardErrorPath</key>
          <string>${home}/Library/Logs/cleanup.stderr.log</string>
        </dict>
        </plist>
      '';
    };
  };

  launchd.agents = lib.mkIf (isDarwin && hostname == "hera") {
    move-audio-files = {
      enable = true;
      config = {
        ProgramArguments = [ "${home}/src/nix/bin/move-audio-files" ];
        StartInterval = 3600;
        StandardOutPath = "${home}/Library/Logs/move-audio-files.stdout.log";
        StandardErrorPath = "${home}/Library/Logs/move-audio-files.stderr.log";
        RunAtLoad = false;
      };
    };

    ollama-serve = {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.ollama}/bin/ollama"
          "serve"
        ];
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${home}/Library/Logs/ollama.log";
        StandardErrorPath = "${home}/Library/Logs/ollama.log";
      };
    };
  };
}
