{ pkgs, claude-code, ... }:

{
  imports = [
    ../../modules/ssh-config-private.nix
    ../../modules/vpn-work.nix
    ../../modules/vpn-home.nix
  ];

  custom.sshConfigPrivate.user = "vdebona";

  nixpkgs.overlays = [ claude-code.overlays.default ];

  hardware.tuxedo-rs = {
    enable = true;
    tailor-gui.enable = true;
  };

  hardware.tuxedo-drivers.settings.fn-lock = false;

  users.users.vdebona = {
    isNormalUser = true;
    description = "Vivien DE BONA";
    extraGroups = [ "networkmanager" "wheel" "docker" "foundryvtt" "foundryvtt-control" ];
    shell = pkgs.fish;
  };

  services.foundryvtt-instances = {
    v14.port = 30014;
  };
  services.foundryvtt-gnome-extension.enable = true;

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
