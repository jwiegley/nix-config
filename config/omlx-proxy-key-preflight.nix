{ pkgs }:

pkgs.writeShellApplication {
  name = "omlx-proxy-key-preflight";
  text = ''
    if [[ $# -ne 3 ]]; then
      echo "usage: omlx-proxy-key-preflight CERTIFICATE PRIVATE_KEY EXPECTED_OWNER" >&2
      exit 64
    fi

    certificate=$1
    private_key=$2
    expected_owner=$3

    if [[ ! -f "$private_key" || -L "$private_key" ]]; then
      echo "oMLX proxy: private key is not a regular host file" >&2
      exit 1
    fi
    if [[ "$(/usr/bin/stat -f '%Su' "$private_key")" != "$expected_owner" \
      || "$(/usr/bin/stat -f '%OLp' "$private_key")" != 600 ]]; then
      echo "oMLX proxy: private key ownership or mode is unsafe" >&2
      exit 1
    fi
    if ! ${pkgs.diffutils}/bin/cmp -s \
      <(${pkgs.openssl}/bin/openssl x509 -in "$certificate" -pubkey -noout) \
      <(${pkgs.openssl}/bin/openssl pkey -in "$private_key" -pubout); then
      echo "oMLX proxy: certificate and private key do not match" >&2
      exit 1
    fi
  '';
}
