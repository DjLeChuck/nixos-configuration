{ pkgs, ... }:

{
  imports = [
    ../../modules/gpg.nix
    ../../modules/vpn-work.nix
    ../../modules/vpn-home.nix
  ];

  custom.gpgImport.user = "vdebona";

  users.users.vdebona = {
    isNormalUser = true;
    description = "Vivien DE BONA";
    extraGroups = [ "networkmanager" "wheel" "docker" "foundryvtt" ];
    shell = pkgs.fish;
  };

  services.foundryvtt-instances = {
    v14.port = 30014;
  };

}
