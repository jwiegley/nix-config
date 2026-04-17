{
  pkgs,
  lib,
  config,
  hostname,
  inputs,
}:

let
  home = config.home.homeDirectory;
  tmpdir = "/tmp";

  inherit (pkgs.stdenv) isDarwin isLinux;

  userName = "John Wiegley";
  userEmail = "johnw@newartisans.com";
  master_key = "4710CF98AF9B327BB80F60E146C4BD1A7AC14BA2";
  signing_key = "12D70076AB504679";

  gitPkg =
    if inputs ? git-ai then inputs.git-ai.packages.${pkgs.stdenv.hostPlatform.system}.default else null;

  ca-bundle_path = "${pkgs.cacert}/etc/ssl/certs/";
  ca-bundle_crt = "${ca-bundle_path}/ca-bundle.crt";
  emacs-server = "${tmpdir}/johnw-emacs/server";
  emacsclient = "${pkgs.emacs}/bin/emacsclient -s ${emacs-server}";

  identityDir = if isDarwin then "${home}/${hostname}" else "${home}/.ssh";
in
{
  inherit
    home
    tmpdir
    isDarwin
    isLinux
    userName
    userEmail
    master_key
    signing_key
    gitPkg
    ca-bundle_path
    ca-bundle_crt
    emacs-server
    emacsclient
    identityDir
    ;
}
