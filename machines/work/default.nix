{ pkgs, ... }:

{
  imports = [
    ../../modules/vpn-work.nix
    ../../modules/vpn-home.nix
    ../../modules/gpg.nix
  ];

  users.users.vdebona = {
    isNormalUser = true;
    description = "Vivien DE BONA";
    extraGroups = [ "networkmanager" "wheel" "docker" "foundryvtt" ];
    shell = pkgs.fish;
  };

  services.foundryvtt-instances = {
    v14.port = 30014;
  };

  custom.gpgImport.user = "vdebona";
}
