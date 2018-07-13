self: super: {

xar = super.xar.overrideAttrs (attrs: {
  buildInputs = attrs.buildInputs ++ [ self.lzma ];
});

}
