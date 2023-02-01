self: pkgs: {

sanoid = pkgs.sanoid.overrideAttrs(attrs: {
  preInstall = ''
    sed -i                                         \
        -e "s%'zfs'%'/usr/local/zfs/bin/zfs'%"     \
        -e "s%'zpool'%'/usr/local/zfs/bin/zpool'%" \
        syncoid
  '';
});

}
