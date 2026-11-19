{ config, ... }:

let
  variables = import ../common/variables.nix;

  homeDomain = "djlechuck.fr";
  # LAN address of the NAS, which also hosts Nginx Proxy Manager.
  homeProxyAddress = variables.nas.hostname;
  # Loopback address dnsmasq listens on (127.0.0.53 and 127.0.0.54 are taken by systemd-resolved's stubs).
  dnsAddress = "127.0.0.100";
in
{
  # The public records for ${homeDomain} point to the box's public IP, which is also the WireGuard
  # endpoint, so it can't be routed through the tunnel. Resolve it to the LAN reverse proxy instead.
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      listen-address = dnsAddress;
      bind-interfaces = true;
      no-resolv = true;
      no-hosts = true;
      address = "/${homeDomain}/${homeProxyAddress}";
    };
  };

  sops.secrets = {
    "vpn-home/private-key".sopsFile = ../secrets/common.yaml;
    "vpn-home/public-key".sopsFile = ../secrets/common.yaml;
    "vpn-home/preshared-key".sopsFile = ../secrets/common.yaml;
    "vpn-home/endpoint".sopsFile = ../secrets/common.yaml;
  };

  sops.templates."vpn-home-env".content = ''
    VPN_HOME_PRIVATE_KEY=${config.sops.placeholder."vpn-home/private-key"}
    VPN_HOME_PUBLIC_KEY=${config.sops.placeholder."vpn-home/public-key"}
    VPN_HOME_PRESHARED_KEY=${config.sops.placeholder."vpn-home/preshared-key"}
    VPN_HOME_ENDPOINT=${config.sops.placeholder."vpn-home/endpoint"}
  '';

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."vpn-home-env".path ];

    profiles."Maison" = {
      connection = {
        id = "Maison";
        type = "wireguard";
        interface-name = "wg-home";
        autoconnect = false;
      };
      wireguard = {
        private-key = "$VPN_HOME_PRIVATE_KEY";
        private-key-flags = 0;
      };
      # Only the tunnel and the home LAN go through the VPN, not all traffic.
      "wireguard-peer.$VPN_HOME_PUBLIC_KEY" = {
        endpoint = "$VPN_HOME_ENDPOINT";
        preshared-key = "$VPN_HOME_PRESHARED_KEY";
        preshared-key-flags = 0;
        allowed-ips = "10.8.0.0/24;192.168.0.0/24;";
      };
      ipv4 = {
        method = "manual";
        address1 = "10.8.0.2/32";
        # Split DNS: only ${homeDomain} goes to the local dnsmasq, everything else keeps using the current network's DNS.
        dns = "${dnsAddress};";
        dns-search = "~${homeDomain};";
      };
      ipv6.method = "ignore";
    };
  };
}
