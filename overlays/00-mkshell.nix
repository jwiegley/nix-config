self: super: {

mkShell = { name, ... }@attr: with super; stdenv.mkDerivation (attr // {
  unpackPhase = ":";

  installPhase = ''
    mkdir -p $out/bin $out/share/nix-shell-${name}
    cp $NIX_BUILD_TOP/env-vars $out/share/nix-shell-${name}/env-vars
    substituteInPlace $out/share/nix-shell-${name}/env-vars --replace "$NIX_BUILD_TOP" '$PWD'
    cat <<-EOF >> $out/share/nix-shell-${name}/env-vars
    installPhase="
      echo >&2
      echo >&2 'This derivation is not meant to be built, aborting'
      echo >&2
      exit 1
    "
    EOF

    cat <<-'EOF' > $out/share/nix-shell-${name}/bashrc
    NIX_BUILD_TOP=$PWD
    PATH=${coreutils}/bin:$PATH
    cp --no-preserve=mode @out@/share/nix-shell-${name}/env-vars $NIX_BUILD_TOP/env-vars
    source @out@/share/nix-shell-${name}/env-vars
    source ${stdenv}/setup
    rm -rf $NIX_BUILD_TOP/env-vars

    dontAddDisableDepTrack=1
    PS1='\n\[\033[1;32m\][${name}-shell:\w]\$\[\033[0m\] '
    unset NIX_ENFORCE_PURITY
    unset NIX_INDENT_MAKE
    unset NIX_LOG_FD
    shopt -u nullglob
    set +e

    runHook shellHook
    EOF

    substituteInPlace $out/share/nix-shell-${name}/bashrc --subst-var out

    cat <<-'EOF' > $out/bin/${name}-shell
    exec ${bashInteractive}/bin/bash --rcfile @out@/share/nix-shell-${name}/bashrc
    EOF

    substituteInPlace $out/bin/${name}-shell --subst-var out
    chmod +x $out/bin/${name}-shell
  '';
});

}

