let
  caches = {
    nixos = {
      url = "https://cache.nixos.org";
      publicKey = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
    };
    iog = {
      url = "https://cache.iog.io";
      publicKey = "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=";
    };
    tron = {
      url = "https://tron.cachix.org";
      publicKey = "tron.cachix.org-1:frKV7mquRWa4U3F0xjUtBehGgDzRofVj328awV2L+dQ=";
    };
  };
  clientSigningPublicKey = "newartisans.com:RmQd/aZOinbJR/G5t+3CIhIxT5NBjlCRvTiSbny8fYw=";
in
{
  inherit clientSigningPublicKey;

  darwin = {
    trustedSubstituters = [
      caches.iog.url
      caches.nixos.url
      caches.tron.url
    ];
    trustedPublicKeys = [
      caches.nixos.publicKey
      clientSigningPublicKey
      caches.iog.publicKey
      caches.tron.publicKey
    ];
  };

  determinateLinux = {
    requireSigs = true;
    trustedUsers = [ "root" ];
    extraSubstituters = [
      caches.tron.url
      caches.iog.url
    ];
    extraTrustedPublicKeys = [
      caches.tron.publicKey
      caches.iog.publicKey
      clientSigningPublicKey
    ];
  };
}
