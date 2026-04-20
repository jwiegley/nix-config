{
  pkgs,
  vars,
  ...
}:
let
  inherit (vars)
    userEmail
    userName
    signing_key
    ca-bundle_crt
    ;
in
{
  accounts.email = {
    certificatesFile = ca-bundle_crt;

    accounts.fastmail = {
      realName = userName;
      address = userEmail;
      aliases = [
        "jwiegley@gmail.com"
        "johnw@gnu.org"
        "jwiegley@positron.ai"
      ];
      flavor = "fastmail.com";
      passwordCommand = "${pkgs.pass}/bin/pass show smtp.fastmail.com";
      primary = true;
      imap = {
        tls = {
          enable = true;
          useStartTls = false;
        };
      };
      smtp = {
        tls = {
          enable = true;
          useStartTls = true;
        };
      };
      gpg = {
        key = signing_key;
        signByDefault = false;
        encryptByDefault = false;
      };
    };
  };
}
