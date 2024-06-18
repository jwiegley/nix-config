self: super: {

dovecot_fts_xapian = super.dovecot_fts_xapian.overrideAttrs(attrs: rec {
  meta = attrs.meta // { broken = false; };
  version = "1.7.13";
  patches = [ ./dovecot/pagesize.patch ];
  src = super.fetchFromGitHub {
    owner = "grosjo";
    repo = "fts-xapian";
    rev = version;
    sha256 = "03m27jgm9v03f5cri9dn3zjlllb45ygdp9szikqd2c0yr83msasr";
    # date = "2024-05-30T12:28:17Z";
  };
});

}
