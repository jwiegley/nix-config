let
  dedicatedLinux = [
    "vulcan"
    "andoria-08"
    "andoria-t2"
    "delphi-3bd4"
    "gpu-server"
  ];
in
{
  inherit dedicatedLinux;

  clients = [
    "hera"
    "clio"
    "vps"
  ]
  ++ dedicatedLinux;
}
