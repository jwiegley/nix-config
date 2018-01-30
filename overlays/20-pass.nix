self: super: {

pass = super.pass.overrideDerivation (attrs: {
  postInstall = attrs.postInstall + ''
    rm -fr "$out/share/emacs"
  '';
});

}
