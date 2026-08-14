{
  lib,
  pkgs,
}:

{
  caBundle,
  package,
}:

pkgs.symlinkJoin {
  inherit (package)
    meta
    name
    passthru
    pname
    version
    ;
  paths = [ package ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/pi" \
      --set-default NODE_EXTRA_CA_CERTS ${lib.escapeShellArg caBundle}
  '';
}
