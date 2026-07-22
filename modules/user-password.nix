{ config, lib, ... }:

let
  cfg = config.custom.userPassword;
in
{
  options.custom.userPassword.user = lib.mkOption {
    type = lib.types.str;
    description = "User whose login password hash is provided via sops.";
  };

  config.sops.secrets."${cfg.user}-password-hash" = {
    sopsFile = ../secrets/user-passwords.yaml;
    neededForUsers = true;
  };

  config.users.users.${cfg.user}.hashedPasswordFile =
    config.sops.secrets."${cfg.user}-password-hash".path;
}
