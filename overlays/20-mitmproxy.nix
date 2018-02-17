self: super: {

mitmproxy = super.mitmproxy.overrideDerivation (attrs: {
  patchPhase = ''
    sed 's/>=\([0-9]\.\?\)\+\( \?, \?<\([0-9]\.\?\)\+\)\?//' -i setup.py
  '';
});

}
