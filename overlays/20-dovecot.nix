self: super: {

dovecot_fts_xapian = super.dovecot_fts_xapian.overrideAttrs(attrs: rec {
  meta = attrs.meta // { broken = false; };
  version = "1.7.10";
  src = super.fetchFromGitHub {
    owner = "grosjo";
    repo = "fts-xapian";
    rev = version;
    sha256 = "sha256-Yd14kla33qAx4Hy0ZdE08javvki3t+hCEc3OTO6YfkQ=";
  };
});

}
