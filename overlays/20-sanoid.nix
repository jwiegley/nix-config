self: pkgs: with pkgs; {

sanoid = pkgs.sanoid.overrideAttrs(attrs: {
  preInstall = ''
    sed -i                                         \
        -e "s%'zfs'%'/usr/local/zfs/bin/zfs'%"     \
        -e "s%'zpool'%'/usr/local/zfs/bin/zpool'%" \
        sanoid
    sed -i                                         \
        -e "s%'zfs'%'/usr/local/zfs/bin/zfs'%"     \
        -e "s%'zpool'%'/usr/local/zfs/bin/zpool'%" \
        syncoid
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    mkdir -p "$out/etc/sanoid"
    cp sanoid.defaults.conf "$out/etc/sanoid/sanoid.defaults.conf"
    # Hardcode path to default config
    substitute sanoid "$out/bin/sanoid" \
      --replace "\$args{'configdir'}/sanoid.defaults.conf" "$out/etc/sanoid/sanoid.defaults.conf"
    chmod +x "$out/bin/sanoid"
    # Prefer ZFS userspace tools from /run/booted-system/sw/bin to avoid
    # incompatibilities with the ZFS kernel module.
    wrapProgram "$out/bin/sanoid" \
      --prefix PERL5LIB : "$PERL5LIB" \
      --prefix PATH : "${lib.makeBinPath [ procps ]}"

    install -m755 syncoid "$out/bin/syncoid"
    wrapProgram "$out/bin/syncoid" \
      --prefix PERL5LIB : "$PERL5LIB" \
      --prefix PATH : "${lib.makeBinPath [ openssh procps which pv lzop gzip pigz ]}"

    install -m755 findoid "$out/bin/findoid"
    wrapProgram "$out/bin/findoid" \
      --prefix PERL5LIB : "$PERL5LIB" \
      --prefix PATH : "${lib.makeBinPath [ ]}"

    runHook postInstall
  '';
});

}
