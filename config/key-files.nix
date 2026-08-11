{ lib, ... }:

hosts: hostname: map (host: ./ssh-keys/id_${host}.pub) (lib.remove hostname hosts)
