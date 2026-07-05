{ pkgs, claude-code, ... }:

{
  imports = [
    ../../modules/gpg.nix
    ../../modules/vpn-work.nix
    ../../modules/vpn-home.nix
  ];

  custom.gpgImport.user = "vdebona";

  nixpkgs.overlays = [ claude-code.overlays.default ];

  users.users.vdebona = {
    isNormalUser = true;
    description = "Vivien DE BONA";
    extraGroups = [ "networkmanager" "wheel" "docker" "foundryvtt" ];
    shell = pkgs.fish;
  };

  services.foundryvtt-instances = {
    v14.port = 30014;
  };

  home-manager.users.vdebona.home.packages = with pkgs; [
    claude-code
  ];
}
