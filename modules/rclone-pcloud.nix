{ config, lib, ... }:

let
  cfg = config.custom.rclonePcloud;
in
{
  options.custom.rclonePcloud.user = lib.mkOption {
    type = lib.types.str;
    description = "User who owns the deployed rclone pCloud remote config, used by claude-sync.";
  };

  config.sops.secrets."rclone-pcloud-conf" = {
    sopsFile = ../secrets/rclone-pcloud.conf;
    format = "binary";
    path = "/home/${cfg.user}/.config/rclone/rclone.conf";
    owner = cfg.user;
    mode = "0400";
  };
}
