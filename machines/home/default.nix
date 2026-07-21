{ config, lib, pkgs, claude-code, ... }:

let
  variables = import ../../common/variables.nix;
in
{
  imports = [
    ../../modules/ansible-vault-passwords.nix
    ../../modules/composer-auth.nix
    ../../modules/ssh-config-private.nix
    ../../modules/vpn-work.nix
  ];

  custom.ansibleVaultPasswords.user = "djlechuck";
  custom.composerAuth.user = "djlechuck";
  custom.sshConfigPrivate.user = "djlechuck";

  # Keep the profile configured (so it's ready when needed) but don't
  # auto-join it on this machine, unlike the other machines using it.
  networking.networkmanager.ensureProfiles.profiles."wifi-home".connection.autoconnect =
    lib.mkForce false;

  fileSystems."/mnt/lechuck" = {
    device = "/dev/disk/by-uuid/68596689-77eb-491f-b306-6676287b46d5";
    fsType = "ext4";
  };

  fileSystems."/home/djlechuck/development" = {
    device = variables.development;
    fsType = "none";
    options = [
      "bind"
      "x-systemd.requires-mounts-for=/mnt/lechuck"
    ];
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
    powerManagement.enable = true;
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

  # This machine is the only one with Logitech hardware, so keep the
  # Solaar Wayland-integration extension out of the common set.
  custom.gnomeExtensionNames = [ "solaar-extension" ];

  # This board's FADT has no "Low Power S0 Idle" bit, so real ACPI S3 ("deep")
  # cuts standby power to USB/PCIe (BIOS "ErP"-style behavior) and wakes only
  # via the power button. s2idle is a software-only sleep state that never
  # cuts that power, restoring keyboard/mouse wakeup without touching the BIOS.
  boot.kernelParams = [ "mem_sleep_default=s2idle" ];

  # This desktop only wakes from suspend via the power button, not
  # keyboard/mouse (Logitech Unifying receiver, hardware.logitech.wireless
  # above): xHCI itself is wakeup-enabled in /proc/acpi/wakeup, but the
  # per-device chain isn't — /sys/bus/usb/devices/*/power/wakeup shows the
  # downstream ports (mouse, receiver) enabled while every hub in between
  # (root hubs + external hubs) is disabled, blocking the wakeup signal from
  # reaching the controller. Match on the USB hub class (09) rather than
  # hardcoding bus/port paths (1-2, 1-3, ...), since those renumber across
  # reboots/re-enumeration.
  #
  # power/control="on" additionally keeps those same hubs from runtime-
  # autosuspending: with s2idle, hubs came back from resume in a stuck
  # half-suspended state where keyboard/mouse input was silently dropped
  # until some unrelated USB (re)connect event on the same hub kicked them
  # out of it (e.g. toggling a headset sharing the mouse's hub).
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{bDeviceClass}=="09", ATTR{power/wakeup}="enabled", ATTR{power/control}="on"
  '';

  home-manager.users.djlechuck =
    { pkgs, ... }:
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

      services.nextcloud-client = {
        enable = true;
        startInBackground = true;
      };

      xdg.configFile."autostart/solaar.desktop".text = ''
        [Desktop Entry]
        Name=Solaar
        Comment=Logitech Unifying Receiver peripherals manager
        Exec=solaar --window=hide
        Icon=solaar
        Terminal=false
        Type=Application
        Categories=Utility;GTK;
      '';

      # FN+F7 ("Screen Capture" HID++ control) -> simulate Print, opening
      # GNOME's screenshot UI. Requires the solaar-extension GNOME Shell
      # extension (custom.gnomeExtensionNames above) for Solaar to reliably
      # synthesize the keypress under Wayland.
      xdg.configFile."solaar/rules.yaml".text = ''
        %YAML 1.3
        ---
        - Key: [Screen Capture, pressed]
        - KeyPress:
          - Print
          - click
      '';

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
