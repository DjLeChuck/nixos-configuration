{ config, lib, pkgs, ... }:

let
  cfg = config.custom.gpgImport;
in
{
  options.custom.gpgImport.user = lib.mkOption {
    type = lib.types.str;
    description = "User for whom the GPG key should be imported.";
  };

  config = {
    sops.secrets."gpg-private-key" = {
      sopsFile = ../secrets/gpg/private-key.asc;
      format = "binary";
      owner = cfg.user;
    };

    systemd.services.gpg-import-key = {
      description = "Import GPG private key into the user keyring";
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ config.sops.secrets."gpg-private-key".path ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
      };
      script = ''
        ${pkgs.gnupg}/bin/gpg --batch --import ${config.sops.secrets."gpg-private-key".path}
      '';
    };
  };
}
