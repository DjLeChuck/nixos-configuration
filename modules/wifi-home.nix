{ config, ... }:

let
  variables = import ../common/variables.nix;
in
{
  sops.secrets."wifi/home-psk" = {
    sopsFile = ../secrets/common.yaml;
  };

  sops.templates."wifi-home-env".content = ''
    WIFI_HOME_PSK=${config.sops.placeholder."wifi/home-psk"}
  '';

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."wifi-home-env".path ];

    profiles."wifi-home" = {
      connection = {
        id = "wifi-home";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        mode = "infrastructure";
        ssid = variables.wifi.home.ssid;
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$WIFI_HOME_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
}
