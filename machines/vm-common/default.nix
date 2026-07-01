{ home-manager, ... }:
{
  imports = [
    home-manager.nixosModules.home-manager
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  system.stateVersion = "26.05";

  users.users.djlechuck.extraGroups = [ "vboxsf" ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "bck";
  home-manager.users.djlechuck = import ../../common/home.nix;
}
