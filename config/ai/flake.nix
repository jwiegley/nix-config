{
  description = "Removed config/ai compatibility stub";
  outputs =
    _:
    throw ''
      nix-config: config/ai was renamed to config/fleet by jwiegley/nix-config#47.
      Update stale ?dir=config/ai references to ?dir=config/fleet.
    '';
}
