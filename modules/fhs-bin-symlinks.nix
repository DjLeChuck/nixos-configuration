# Some team tooling (shared shell scripts, git hooks, IDE run configs) hardcodes
# absolute binary paths like /usr/bin/xxx, which don't exist on NixOS by default.
# This keeps a symlink at each configured path pointing into the Nix store, so
# the binary stays managed/installed the normal Nix way while also being
# reachable at the path that tooling expects. Populate custom.fhsBinSymlinks
# with more entries as needed.
{ config, lib, pkgs, ... }:

let
  cfg = config.custom.fhsBinSymlinks;
in
{
  options.custom.fhsBinSymlinks = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      "/usr/bin/php" = "${pkgs.php84}/bin/php";
    };
    description = ''
      Mapping of absolute filesystem paths to the Nix store path (or any
      absolute path) they should symlink to. Applied on every activation.
    '';
  };

  config.system.activationScripts.fhsBinSymlinks = lib.stringAfter [ "users" ] (
    lib.concatStrings (
      lib.mapAttrsToList (path: target: ''
        mkdir -p "$(dirname ${lib.escapeShellArg path})"
        ln -sfn ${lib.escapeShellArg target} ${lib.escapeShellArg path}
      '') cfg
    )
  );
}
