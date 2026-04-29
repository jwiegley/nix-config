{
  pkgs,
  config,
  hostname,
  inputs,
  ...
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
    if inputs ? git-ai then
      inputs.git-ai.packages.${pkgs.stdenv.hostPlatform.system}.default
    else
      pkgs.git;

  # Use the merged bundle (system + Vulcan CA) when our overlay is loaded;
  # otherwise fall back to the stock cacert. NixOS hosts that don't import
  # config/overlays.nix should add the Vulcan CA via security.pki.certificateFiles.
  ca-bundle_pkg = pkgs.ca-bundle-with-vulcan or pkgs.cacert;
  ca-bundle_path = "${ca-bundle_pkg}/etc/ssl/certs/";
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
