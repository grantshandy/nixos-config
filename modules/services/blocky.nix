# Tailnet DNS with ad blocking.
{
  fleet.aspects.blocky.tags = ["tailnet-dns"];

  flake.modules.nixos.blocky = {...}: {
    services.blocky = {
      enable = true;

      settings = {
        ports.dns = 53;

        upstreams.groups.default = [
          "https://dns.quad9.net/dns-query"
          "https://cloudflare-dns.com/dns-query"
        ];

        bootstrapDns = [
          {
            upstream = "https://dns.quad9.net/dns-query";
            ips = ["9.9.9.9" "149.112.112.112"];
          }
          {
            upstream = "https://cloudflare-dns.com/dns-query";
            ips = ["1.1.1.1" "1.0.0.1"];
          }
        ];

        blocking = {
          denylists.ads = [
            # "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro-onlydomains.txt"
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
  };
}
