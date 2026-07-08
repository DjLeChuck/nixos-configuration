{ config, lib, pkgs, claude-code, ... }:

let
  variables = import ../../common/variables.nix;
in
{
  imports = [
    ../../modules/gpg.nix
    ../../modules/ssh-config-private.nix
    ../../modules/vpn-work.nix
  ];

  custom.gpgImport.user = "djlechuck";
  custom.sshConfigPrivate.user = "djlechuck";

  # Keep the profile configured (so it's ready when needed) but don't
  # auto-join it on this machine, unlike the other machines using it.
  networking.networkmanager.ensureProfiles.profiles."wifi-home".connection.autoconnect =
    lib.mkForce false;

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
  services.foundryvtt-gnome-extension.enable = true;

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
    extraGroups = [ "networkmanager" "wheel" "docker" "vboxusers" "foundryvtt" "foundryvtt-control" ];
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

      home.file."development".source = config.lib.file.mkOutOfStoreSymlink variables.development;

      # networking.hostName ("djlechuck-linux") doesn't match this flake's
      # nixosConfigurations attribute name ("home"), so `nh os` can't infer
      # it automatically — pin it explicitly.
      programs.fish.interactiveShellInit = ''
        set -gx NH_OS_FLAKE "$NIXOS_CONFIG_DIR#home"
      '';
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
