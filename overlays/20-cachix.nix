self: super: {

inherit (super.callPackage (builtins.fetchTarball {
    url = "https://cachix.org/api/v1/install";
    sha256 = "0bjjijvqn6b8hay7bh0rijrp5299wjldc0gc5izpbn00z6cgd1wr";
  }) {}) cachix;

}
