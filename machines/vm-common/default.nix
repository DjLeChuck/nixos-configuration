{ home-manager, pkgs, toggl-redmine, ... }:
{
  imports = [
    home-manager.nixosModules.home-manager
    ../../modules/vpn-home.nix
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  system.stateVersion = "26.05";

  users.users.djlechuck = {
    isNormalUser = true;
    description = "DjLeChuck";
    extraGroups = [ "networkmanager" "wheel" "docker" "vboxsf" ];
    shell = pkgs.fish;
    hashedPassword = "$6$MwGByc4Pbzv7QYaD$91kzkjvPMNgndWAQeYITb3sZrDhAVWzLayuNCeEfPlftU9QzyXJCn12dj1D.WcbH3Je57eWU2TPPEU8x/O6Ke.";
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "bck";
  home-manager.extraSpecialArgs = { inherit toggl-redmine; };
  home-manager.users.djlechuck = import ../../common/home.nix;
}
