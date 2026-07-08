{ config, lib, ... }:

let
  cfg = config.custom.sshConfigPrivate;
in
{
  options.custom.sshConfigPrivate.user = lib.mkOption {
    type = lib.types.str;
    description = "User who owns the decrypted HTTPS token used to clone the private ~/.ssh/config.d repository.";
  };

  config.sops.secrets."ssh-config-private-token" = {
    sopsFile = ../secrets/ssh-config-private.yaml;
    owner = cfg.user;
  };
}
