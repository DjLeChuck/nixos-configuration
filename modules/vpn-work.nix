{ config, lib, pkgs, ... }:

let
  configs = {
    UmanIT = config.sops.secrets."vpn-work-config-main".path;
    "UmanIT - Secours" = config.sops.secrets."vpn-work-config-backup".path;
  };

  importScript = pkgs.writeShellScript "openvpn3-import-configs" ''
    set -eu
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path: ''
      if ! ${pkgs.openvpn3}/bin/openvpn3 config-manage --config "${name}" --exists; then
        ${pkgs.openvpn3}/bin/openvpn3 config-import --config "${path}" --name "${name}" --persistent
      fi
      ${pkgs.openvpn3}/bin/openvpn3 config-acl --config "${name}" --public-access true
    '') configs)}
  '';
in
{
  programs.openvpn3.enable = true;

  sops.secrets."vpn-work-config-main" = {
    sopsFile = ../secrets/vpn-work/config-main.ovpn;
    format = "binary";
  };
  sops.secrets."vpn-work-config-backup" = {
    sopsFile = ../secrets/vpn-work/config-backup.ovpn;
    format = "binary";
  };

  systemd.services.openvpn3-import-configs = {
    description = "Import OpenVPN3 work VPN configs";
    wantedBy = [ "multi-user.target" ];
    restartTriggers = builtins.attrValues configs;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${importScript}";
    };
  };
}
