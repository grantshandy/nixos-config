{...}: {
  services.blocky = {
    enable = true;

    settings = {
      ports.dns = 53;

      upstreams.groups.default = [
        "https://dns.quad9.net/dns-query"
        "https://cloudflare-dns.com/dns-query"
      ];

      blocking = {
        denylists.ads = [
          "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt"
        ];
        clientGroupsBlock.default = ["ads"];
        blockType = "zeroIp";
        loading.refreshPeriod = "24h";
      };

      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };
    };
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [53];
    allowedUDPPorts = [53];
  };
}
