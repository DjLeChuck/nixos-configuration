{ config, pkgs, ... }:

{
  imports = [ ../../modules/vpn-work.nix ];

  services.foundryvtt-instances = {
    v11.port = 30011;
    v12.port = 30012;
    v13.port = 30013;
    v14.port = 30014;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  hardware.graphics.enable32Bit = true;

  virtualisation.virtualbox.host = {
    enable = true;
    enableExtensionPack = true;
  };

  users.users.djlechuck = {
    isNormalUser = true;
    description = "DjLeChuck";
    extraGroups = [ "networkmanager" "wheel" "docker" "vboxusers" "foundryvtt" ];
    shell = pkgs.fish;
  };

  environment.systemPackages = with pkgs; [
    gamescope
    lutris
    mumble
    wineWowPackages.stable
    winetricks
  ];

  programs.gamemode.enable = true;

  programs.ghidra = {
    enable = true;
    gdb = true;
  };

  programs.steam = {
    enable = true;
    localNetworkGameTransfers.openFirewall = true;
    remotePlay.openFirewall = true;
  };
}
