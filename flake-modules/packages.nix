# perSystem packages: the hand-built openvpn3-switcher GNOME extension
# (always) and the two private GitLab CLI tools (gated on
# variables.privateTools.enable, same condition common/configuration.nix and
# common/home.nix use to decide whether to reference them at all).
{ ... }:

let
  variables = import ../common/variables.nix;
in
{
  perSystem = { pkgs, lib, ... }:
    let
      privateTools = import ../pkgs/private-tools.nix { inherit pkgs variables; };
    in
    {
      packages =
        {
          openvpn3-switcher = import ../gnome-extensions/openvpn3-switcher { inherit pkgs; };
        }
        // lib.optionalAttrs variables.privateTools.enable {
          inherit (privateTools) lock-excel excel2jsonl;
        };
    };
}
