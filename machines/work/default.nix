{ pkgs, ... }:

{
  users.users.vdebona = {
    isNormalUser = true;
    description = "Vivien DE BONA";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    shell = pkgs.fish;
  };
}
