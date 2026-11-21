# Temporary bridge for the router's existing TCP 443 port forward to Radon.
# Remove this import and module after forwarding TCP 443 directly to Krypton.
{
  networking = {
    nat = {
      forwardPorts = [
        {
          proto = "tcp";
          sourcePort = 443;
          destination = "192.168.86.46:443";
        }
      ];

      # Radon and Krypton are on the same interface and subnet. Mark these
      # connections before DNAT so the existing NixOS NAT postrouting chain
      # masquerades them and sends Krypton's replies back through Radon.
      extraCommands = ''
        iptables -t nat -I nixos-nat-pre 1 -i enp8s0 -p tcp --dport 443 -j MARK --set-mark 1
      '';
    };

    firewall = {
      extraCommands = ''
        iptables -I FORWARD 1 -i enp8s0 -o enp8s0 -p tcp -d 192.168.86.46 --dport 443 -j ACCEPT
      '';
      extraStopCommands = ''
        iptables -D FORWARD -i enp8s0 -o enp8s0 -p tcp -d 192.168.86.46 --dport 443 -j ACCEPT 2>/dev/null || true
      '';
    };
  };
}
