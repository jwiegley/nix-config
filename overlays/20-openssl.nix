self: super: {

openssl_1_0_2 = super.openssl_1_0_2.overrideAttrs(attrs: {
  meta = builtins.removeAttrs attrs.meta [ "knownVulnerabilities" ];
});

}
