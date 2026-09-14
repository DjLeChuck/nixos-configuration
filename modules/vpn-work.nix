{
  config,
  lib,
  pkgs,
  ...
}:

let
  configs = {
    UmanIT = config.sops.secrets."vpn-work-config-main".path;
    "UmanIT - Secours" = config.sops.secrets."vpn-work-config-backup".path;
  };

  importScript = pkgs.writeShellScript "openvpn3-import-configs" ''
    set -eu
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: path: ''
        if ! ${pkgs.openvpn3}/bin/openvpn3 config-manage --config "${name}" --exists; then
          ${pkgs.openvpn3}/bin/openvpn3 config-import --config "${path}" --name "${name}" --persistent
        fi
        ${pkgs.openvpn3}/bin/openvpn3 config-acl --config "${name}" --public-access true
      '') configs
    )}
  '';

  suspendDisconnectScript = pkgs.writeShellScript "openvpn3-suspend-disconnect" ''
    set -u

    # This service runs as root, but OpenVPN3 sessions are only visible to
    # and manageable by the UID that started them (root has no implicit
    # access, unlike config-acl's --public-access) — confirmed by journal
    # logs showing "No sessions available" as root while a session was
    # actually active. So the actual openvpn3 calls must run as the desktop
    # user that owns the session, resolved dynamically since this module is
    # shared between machines with different usernames.
    #
    # seat0's ActiveSession is unreliable right at the suspend/resume
    # transition (observed empty in the journal at both points, causing this
    # to silently skip every time), so use the logged-in user list instead,
    # which doesn't depend on VT/seat focus.
    target_user=""
    while read -r uid user _; do
      if [ "$uid" != "0" ] && [ -n "$user" ]; then
        target_user="$user"
        break
      fi
    done < <(${pkgs.systemd}/bin/loginctl list-users --no-legend 2>/dev/null)
    if [ -z "$target_user" ]; then
      echo "openvpn3-suspend-disconnect: could not resolve a logged-in desktop user, skipping" >&2
      exit 0
    fi

    run_as_user() {
      ${pkgs.util-linux}/bin/runuser -u "$target_user" -- ${pkgs.openvpn3}/bin/openvpn3 "$@"
    }

    # Same parsing approach as gnome-extensions/openvpn3-switcher/extension.js:
    # sessions-list has no --json output; blocks are dashed-line separated,
    # each with a "Config name:" line if a session is active for it.
    session_names() {
      run_as_user sessions-list 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oP '^\s*Config name:\s*\K.+'
    }

    # `session-manage --disconnect` acks the request without waiting for the
    # actual teardown: a session that's mid-(re)connect can ignore it and
    # keep retrying for a long time (observed ~50s) before it actually drops.
    # Keep re-issuing the disconnect and re-checking sessions-list until it's
    # genuinely empty, instead of firing once and assuming it worked.
    attempt=0
    while [ "$attempt" -lt 20 ]; do
      names="$(session_names)"
      [ -z "$names" ] && exit 0
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        echo "openvpn3-suspend-disconnect: disconnecting '$name' as $target_user (attempt $((attempt + 1)))" >&2
        run_as_user session-manage --config "$name" --disconnect || true
      done <<< "$names"
      sleep 3
      attempt=$((attempt + 1))
    done
    echo "openvpn3-suspend-disconnect: session(s) still present after retrying: $(session_names)" >&2
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
    description = "Disconnect any active OpenVPN3 work VPN session around suspend/resume";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Headroom above the script's own ~60s retry loop (see
      # suspendDisconnectScript) so systemd doesn't kill it mid-retry.
      TimeoutSec = "120s";
      ExecStart = "${suspendDisconnectScript}";
      ExecStop = "${suspendDisconnectScript}";
    };
  };
}
