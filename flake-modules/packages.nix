# perSystem packages: the two private GitLab CLI tools (gated on
# variables.privateTools.enable, same condition common/configuration.nix and
# common/home.nix use to decide whether to reference them at all).
{ ... }:

let
  variables = import ../common/variables.nix;
in
{
  perSystem =
    { pkgs, lib, ... }:
    let
      privateTools = import ../pkgs/private-tools.nix { inherit pkgs variables; };
    in
    {
      packages = lib.optionalAttrs variables.privateTools.enable {
        inherit (privateTools) lock-excel excel2jsonl;
      };
    };
}
