{ pkgs, ... }:

{
  imports = [
    ../../modules/vpn-work.nix
    ../../modules/vpn-home.nix
  ];

  users.users.vdebona = {
    isNormalUser = true;
    description = "Vivien DE BONA";
    extraGroups = [ "networkmanager" "wheel" "docker" "foundryvtt" ];
    shell = pkgs.fish;
  };

  services.foundryvtt-instances = {
    v11.port = 30011;
    v12.port = 30012;
    v13.port = 30013;
    v14.port = 30014;
  };
}
