# Share Xenon's Wi-Fi internet connection with Krypton over direct Ethernet.
{...}: let
  ethernetInterface = "enp42s0";
  wifiInterface = "wlo1";
  serverAddress = "10.42.0.1";
in {
  networking = {
    # NetworkManager waits for Ethernet carrier before assigning an address.
    # Keep this dedicated link under networkd so sharing is ready before the
    # powered-off Krypton brings the link up.
    networkmanager.unmanaged = [ethernetInterface];

    nat = {
      enable = true;
      externalInterface = wifiInterface;
      internalInterfaces = [ethernetInterface];
    };

    firewall.interfaces.${ethernetInterface} = {
      allowedUDPPorts = [
        53 # DNS
        67 # DHCP
      ];
      allowedTCPPorts = [53]; # DNS
    };
  };

  systemd.network = {
    enable = true;
    # NetworkManager owns the real uplink, and this isolated link must not hold
    # network-online.target while Krypton is powered off.
    wait-online.enable = false;
    networks."40-krypton" = {
      matchConfig.Name = ethernetInterface;
      address = ["${serverAddress}/24"];
      networkConfig = {
        ConfigureWithoutCarrier = true;
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
      linkConfig.RequiredForOnline = "no";
    };
  };

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      interface = ethernetInterface;
      # Unlike bind-interfaces, this tolerates the NIC disappearing briefly
      # during a NixOS switch and starts serving as soon as it is available.
      bind-dynamic = true;

      dhcp-range = "10.42.0.10,10.42.0.100,255.255.255.0,12h";
      dhcp-option = [
        "option:router,${serverAddress}"
        "option:dns-server,${serverAddress}"
      ];
    };
  };
}
