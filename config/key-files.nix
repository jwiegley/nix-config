{ lib, ... }:

hosts: home: hostname:
let
  # Create an entry for each host with public keys of all other hosts
  makeKeyEntry =
    host:
    lib.nameValuePair host (
      lib.filter (x: x != null) (
        map (otherHost: if otherHost != host then ./ssh-keys/id_${otherHost}.pub else null) hosts
      )
    );

  # Generate the entire structure by mapping over all hosts
  keyFilesAttr = builtins.listToAttrs (map makeKeyEntry hosts);
  # Return the entry for the current hostname
in
keyFilesAttr.${hostname}
