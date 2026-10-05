{ config, lib, ... }:

let
  cfg = config.custom.pcloudRsync;
in
{
  options.custom.pcloudRsync.user = lib.mkOption {
    type = lib.types.str;
    description = "User who owns the deployed pCloud account password, used by claude-sync's rsync-over-SSH transfers.";
  };

  config.sops.secrets."pcloud-rsync-password" = {
    sopsFile = ../secrets/pcloud-rsync-password;
    format = "binary";
    path = "/home/${cfg.user}/.config/pcloud-rsync-password";
    owner = cfg.user;
    mode = "0400";
  };
}
