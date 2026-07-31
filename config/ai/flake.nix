{
  description = "Removed config/ai compatibility stub";
  # Existing consumers follow this key before they force our outputs. Retain the
  # key so they reach the actionable throw instead of failing at lock topology.
  inputs.llm-agents.url = "github:numtide/llm-agents.nix";
  outputs =
    _:
    throw ''
      nix-config: config/ai was renamed to config/fleet by jwiegley/nix-config#47.
      Update stale ?dir=config/ai references to ?dir=config/fleet.
    '';
}
