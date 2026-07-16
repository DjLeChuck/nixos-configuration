# Extra GNOME Shell extension names (as exposed under `pkgs.gnomeExtensions`) for
# machines that need something beyond the common set in
# ../common/gnome-extension-names.nix - e.g. an extension tied to hardware that
# isn't present on every machine.
{ lib, ... }:
{
  options.custom.gnomeExtensionNames = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "solaar-extension" ];
    description = ''
      Extra GNOME Shell extension attribute names to install and enable on
      this machine, in addition to the common set.
    '';
  };
}
