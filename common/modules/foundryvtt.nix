{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.foundryvtt-instances;

  primaryUser = lib.head (lib.attrNames (
    lib.filterAttrs (_: u: u.isNormalUser) config.users.users
  ));

  instanceModule = { name, config, ... }: {
    options = {
      user = mkOption {
        type = types.str;
        default = primaryUser;
        description = "System user this instance's service and files belong to. Defaults to the machine's primary user (the one with isNormalUser = true).";
      };

      port = mkOption {
        type = types.port;
        description = "TCP port this FoundryVTT instance listens on.";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/home/${config.user}/foundryvtt/data/${name}";
        description = "FoundryVTT data directory for this instance.";
      };

      appDir = mkOption {
        type = types.str;
        default = "/home/${config.user}/foundryvtt/app/${name}";
        description = "Directory this instance's FoundryVTT software is unpacked into at service start.";
      };

      archive = mkOption {
        type = types.str;
        default = "/home/${config.user}/foundryvtt/releases/${name}.zip";
        description = "Manually downloaded FoundryVTT .zip archive for this version.";
      };

      nodePackage = mkOption {
        type = types.package;
        default = pkgs.nodejs;
        description = "Node.js package used to run this instance (override if the version requires an older one).";
      };
    };
  };

  mkFoundryService = name: instance: {
    description = "FoundryVTT (${name})";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStartPre = "${pkgs.runtimeShell} -c 'test -e ${instance.appDir}/main.js || ${pkgs.unzip}/bin/unzip -q ${instance.archive} -d ${instance.appDir}'";
      ExecStart = "${instance.nodePackage}/bin/node ${instance.appDir}/main.js --port=${toString instance.port} --dataPath=${instance.dataDir}";
      User = instance.user;
      Group = "users";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
in
{
  options.services.foundryvtt-instances = mkOption {
    type = types.attrsOf (types.submodule instanceModule);
    default = { };
    description = "FoundryVTT instances to run in parallel (one per version).";
  };

  config = {
    systemd.services = mapAttrs' (name: instance:
      nameValuePair "foundryvtt-${name}" (mkFoundryService name instance)
    ) cfg;

    systemd.tmpfiles.rules = unique (flatten (mapAttrsToList (_: instance: [
      "d ${builtins.dirOf instance.dataDir} 0750 ${instance.user} users - -"
      "d ${instance.dataDir} 0750 ${instance.user} users - -"
      "d ${builtins.dirOf instance.appDir} 0750 ${instance.user} users - -"
      "d ${instance.appDir} 0750 ${instance.user} users - -"
    ]) cfg));
  };
}
