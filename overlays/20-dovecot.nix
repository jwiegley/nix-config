self: super: {

dovecot_fts_xapian = super.dovecot_fts_xapian.overrideAttrs(attrs: {
  meta = attrs.meta // { broken = false; };
});

}
