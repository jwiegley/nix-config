self: super: {

gitAndTools = super.gitAndTools // {
  # This currently fails three tests, all of which output the following:
  #   gpg: can't connect to the agent: IPC connect call failed
  #   gpg: error getting the KEK: No agent running
  #   gpg: error reading '[stdin]': No agent running
  #   gpg: import from '[stdin]' failed: No agent running
  git-annex = super.haskell.lib.dontCheck super.gitAndTools.git-annex;
};

}
