{}: (import ./darwin {
       configuration = ./config/darwin.nix;
       pkgs          = import ./nixpkgs {};
     }).system
