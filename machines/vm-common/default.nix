{ pkgs, ... }:
{
  imports = [
    ../../modules/ansible-vault-passwords.nix
    ../../modules/vpn-home.nix
  ];

  custom.ansibleVaultPasswords.user = "djlechuck";

  users.users.djlechuck = {
    isNormalUser = true;
    description = "DjLeChuck";
    extraGroups = [ "networkmanager" "wheel" "docker" "vboxsf" ];
    shell = pkgs.fish;
    hashedPassword = "$6$MwGByc4Pbzv7QYaD$91kzkjvPMNgndWAQeYITb3sZrDhAVWzLayuNCeEfPlftU9QzyXJCn12dj1D.WcbH3Je57eWU2TPPEU8x/O6Ke.";
  };
}
