let
  # Personal SSH keys double as recovery recipients, so the secret can be
  # edited away from radon. Keep this list centralized in identity.nix.
  identity = (import ../identity.nix).identity;
  users = identity.user.sshKeys;

  # ssh-keyscan radon, or copy /etc/ssh/ssh_host_ed25519_key.pub from radon.
  # The matching private host key lets agenix decrypt during activation.
  systems = {
    radon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDskTTcyiRpEPJoKOAi7L8Bxv+BQBKjjDW6hz5ctWXOB";
  };
in {
  "duckdns-token.age".publicKeys = users ++ [systems.radon];
}
