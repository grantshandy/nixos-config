let
  ssh = (import ../identity.nix).identity.ssh;
in {
  "duckdns-token.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
}
