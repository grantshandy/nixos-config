let
  ssh = (import ../identity.nix).identity.ssh;
in {
  "authelia-bootstrap-password.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "authelia-jwt-secret.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "authelia-oidc-hmac-secret.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "authelia-oidc-private-key.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "authelia-storage-encryption-key.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "authelia-users.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "duckdns-token.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "gitlab-runner-token.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "immich-oidc-client-secret.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
  "nix-cache-private-key.age".publicKeys = ssh.userKeys ++ builtins.attrValues ssh.hostKeys;
  "slskd-environment.age".publicKeys = ssh.userKeys ++ [ssh.hostKeys.radon];
}
