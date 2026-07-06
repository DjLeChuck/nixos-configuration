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

  # networking.hostName ("LIN-2025-1") doesn't match this flake's
  # nixosConfigurations attribute name ("work"), so `nh os` can't infer
  # it automatically — pin it explicitly.
  home-manager.users.vdebona.programs.fish.interactiveShellInit = ''
    set -gx NH_OS_FLAKE "$NIXOS_CONFIG_DIR#work"
  '';
}
