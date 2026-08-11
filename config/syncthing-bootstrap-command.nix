{
  defaultPolicy,
  desktopDirectory,
  documentsDirectory,
  guiSocket,
  lib,
  listenAddress,
  localDeviceID,
  mode,
  peerPolicies,
  program,
  stateDirectory,
}:

lib.escapeShellArgs (
  [
    program
    mode
    "--config"
    "${stateDirectory}/config.xml"
    "--local-device-id"
    localDeviceID
    "--listen-address"
    listenAddress
  ]
  ++ lib.concatMap (policy: [
    "--peer-policy"
    (builtins.toJSON policy)
  ]) peerPolicies
  ++ [
    "--gui-socket"
    guiSocket
    "--default-policy"
    (builtins.toJSON defaultPolicy)
    "--documents"
    documentsDirectory
    "--desktop"
    desktopDirectory
  ]
)
