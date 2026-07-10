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

  suspendDisconnectScript = pkgs.writeShellScript "openvpn3-suspend-disconnect" ''
    set -u
    # Same parsing approach as gnome-extensions/openvpn3-switcher/extension.js:
    # sessions-list has no --json output; blocks are dashed-line separated,
    # each with a "Config name:" line if a session is active for it.
    ${pkgs.openvpn3}/bin/openvpn3 sessions-list 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -oP '^\s*Config name:\s*\K.+' \
      | while IFS= read -r name; do
          [ -n "$name" ] || continue
          ${pkgs.openvpn3}/bin/openvpn3 session-manage --config "$name" --disconnect || true
        done
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

  systemd.services.openvpn3-suspend-disconnect = {
    description = "Disconnect any active OpenVPN3 work VPN session before suspend";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${suspendDisconnectScript}";
    };
  };
}
