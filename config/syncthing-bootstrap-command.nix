{
  defaultPolicy,
  desktopDirectory,
  documentsDirectory,
  guiSocket,
  lib,
  listenAddresses,
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
  ]
  ++ lib.concatMap (address: [
    "--listen-address"
    address
  ]) listenAddresses
  ++ [
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
