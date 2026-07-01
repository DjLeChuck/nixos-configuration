{ config, pkgs, ... }:

{
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

  users.users.djlechuck.extraGroups = [ "vboxusers" ];

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
