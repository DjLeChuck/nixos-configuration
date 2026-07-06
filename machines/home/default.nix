{ config, pkgs, claude-code, ... }:

{
  imports = [
    ../../modules/gpg.nix
    ../../modules/vpn-work.nix
  ];

  custom.gpgImport.user = "djlechuck";

  fileSystems."/mnt/lechuck" = {
    device = "/dev/disk/by-uuid/68596689-77eb-491f-b306-6676287b46d5";
    fsType = "ext4";
  };

  nixpkgs.overlays = [ claude-code.overlays.default ];

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
    uid = 1000;
    description = "DjLeChuck";
    extraGroups = [ "networkmanager" "wheel" "docker" "vboxusers" "foundryvtt" ];
    shell = pkgs.fish;
  };
  users.groups.djlechuck.gid = 1000;

  hardware.logitech.wireless.enable = true;

  home-manager.users.djlechuck =
    { config, pkgs, ... }:
    {
      home.packages = with pkgs; [
        pkgs.claude-code
        gamescope
        lutris
        mumble
        solaar
        wineWow64Packages.stable
        winetricks
      ];

      home.file."development".source = config.lib.file.mkOutOfStoreSymlink "/mnt/lechuck/development";
    };

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
