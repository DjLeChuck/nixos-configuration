{ config, pkgs, ... }:

let
  importedName = "wg-home";
  displayName = "Maison";

  importScript = pkgs.writeShellScript "networkmanager-import-vpn-home" ''
    set -eu
    if ! ${pkgs.networkmanager}/bin/nmcli -g NAME connection show | grep -qx "${displayName}"; then
      ${pkgs.networkmanager}/bin/nmcli connection import type wireguard file "${config.sops.secrets."vpn-home-config".path}"
      ${pkgs.networkmanager}/bin/nmcli connection modify "${importedName}" connection.id "${displayName}"
    fi
    ${pkgs.networkmanager}/bin/nmcli connection modify "${displayName}" connection.autoconnect no
  '';
in
{
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
    restartTriggers = [ config.sops.secrets."vpn-home-config".path ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${importScript}";
    };
  };
}
