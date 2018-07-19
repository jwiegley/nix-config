self: super: {

# The tests for fqdm were broken by this commit:
# https://github.com/NixOS/nixpkgs/commit/f2f7c4287ff257e7c219737b0d7416a7965c0c3e
backblaze-b2 = super.backblaze-b2.override {
  tqdm = super.python2Packages.tqdm.overridePythonAttrs (_: {
    doCheck = false;
  });
};

}
