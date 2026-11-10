{ config, pkgs, ... }:

let
  importedName = "wg-home";
  displayName = "Maison";

  variables = import ../common/variables.nix;

  homeDomain = "djlechuck.fr";
  # LAN address of the NAS, which also hosts Nginx Proxy Manager.
  homeProxyAddress = variables.nas.hostname;
  # Loopback address dnsmasq listens on (127.0.0.53 and 127.0.0.54 are taken by systemd-resolved's stubs).
  dnsAddress = "127.0.0.100";

  importScript = pkgs.writeShellScript "networkmanager-import-vpn-home" ''
    set -eu
    # Always re-import so changes to the sops config (AllowedIPs, DNS...) are applied.
    ${pkgs.networkmanager}/bin/nmcli connection delete "${displayName}" || true
    ${pkgs.networkmanager}/bin/nmcli connection import type wireguard file "${
      config.sops.secrets."vpn-home-config".path
    }"
    ${pkgs.networkmanager}/bin/nmcli connection modify "${importedName}" connection.id "${displayName}"
    # Split DNS: only ${homeDomain} goes to the local dnsmasq, everything else keeps using the current network's DNS.
    ${pkgs.networkmanager}/bin/nmcli connection modify "${displayName}" \
      connection.autoconnect no \
      ipv4.dns "${dnsAddress}" \
      ipv4.dns-search "~${homeDomain}"
  '';
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

  sops.secrets."vpn-home-config" = {
    sopsFile = ../secrets/vpn-home/home.conf;
    format = "binary";
    path = "/run/secrets/${importedName}.conf";
  };

  systemd.services.networkmanager-import-vpn-home = {
    description = "Import WireGuard home VPN into NetworkManager";
    after = [ "NetworkManager.service" ];
    wants = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    # The runtime secret path is constant, so trigger on the encrypted file's content instead.
    restartTriggers = [ ../secrets/vpn-home/home.conf ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${importScript}";
    };
  };
}
