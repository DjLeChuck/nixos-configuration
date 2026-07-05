{ config, lib, ... }:

let
  cfg = config.custom.gpgImport;
in
{
  options.custom.gpgImport.user = lib.mkOption {
    type = lib.types.str;
    description = "User who owns the decrypted GPG private key secret.";
  };

  config.sops.secrets."gpg-private-key" = {
    sopsFile = ../secrets/gpg/private-key.asc;
    format = "binary";
    owner = cfg.user;
  };
}
