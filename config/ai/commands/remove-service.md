I want you to remove the $ARGUMENTS service from this NixOS host, including nginx virtual hosts, monitoring, alerting, systemd services and timers, containers, Nagios, Alertmanager, Prometheus exporters, etc.

I want you to completely, fully and thoroughly remove this service from this machine, including all related configuration files, users, directories, data, etc. Do not perform this removal directly, however, rather generate a script that I can run at a later time that will carry out all of the action you would have performed. You are entirely free, although, to remove declarations from the Nix files, but leave cleanup of the SOPS secrets to me.

Everything you do should be coherent with the other services on this NixOS machine. Do not reveal ANY secrets during this chat, and always ask me if you need to create a new SOPS secret or you need to create a Web SSL certificate.

Use Web Search and Perplexity MCP as needed to discover what is the best way to fully remove the $ARGUMENTS service. Some further notes:

Use the nixos skill to perform your work on these removal steps. Take as long as needed to ensure that the service is fully removed, that the remaining configuration stays coherent with the rest of this machine’s services, and that everything else continues functioning well before you are finished.
