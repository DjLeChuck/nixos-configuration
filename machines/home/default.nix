{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../modules/ansible-vault-passwords.nix
    ../../modules/composer-auth.nix
    ../../modules/rclone-pcloud.nix
    ../../modules/ssh-config-private.nix
    ../../modules/user-password.nix
    ../../modules/vpn-work.nix
  ];

  custom.ansibleVaultPasswords.user = "djlechuck";
  custom.composerAuth.user = "djlechuck";
  custom.rclonePcloud.user = "djlechuck";
  custom.sshConfigPrivate.user = "djlechuck";
  custom.userPassword.user = "djlechuck";

  # Keep the profile configured (so it's ready when needed) but don't
  # auto-join it on this machine, unlike the other machines using it.
  networking.networkmanager.ensureProfiles.profiles."wifi-home".connection.autoconnect =
    lib.mkForce false;

  fileSystems."/mnt/lechuck" = {
    device = "/dev/disk/by-uuid/68596689-77eb-491f-b306-6676287b46d5";
    fsType = "ext4";
  };

  fileSystems."/srv/development" = {
    device = "/mnt/lechuck/development";
    fsType = "none";
    options = [
      "bind"
      "x-systemd.requires-mounts-for=/mnt/lechuck"
    ];
  };

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

  users.users.djlechuck = {
    isNormalUser = true;
    uid = 1000;
    description = "DjLeChuck";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "foundryvtt"
      "foundryvtt-control"
    ];
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
    { config, pkgs, ... }:
    {
      home.packages = with pkgs; [
        gamescope
        lutris
        mumble
        solaar
        wineWow64Packages.stable
        winetricks
      ];

      programs.mangohud = {
        enable = true;
        settings = {
          legacy_layout = false;
          background_alpha = 0.6;
          round_corners = false;
          background_color = "000000";
          font_size = 24;
          text_color = "FFFFFF";
          position = "top-left";
          toggle_hud = "Shift_R+F12";
          gpu_list = false;
          table_columns = 3;
          gpu_text = "GPU";
          gpu_stats = true;
          gpu_load_change = true;
          gpu_load_value = [
            50
            90
          ];
          gpu_load_color = [
            "FFFFFF"
            "FFAA7F"
            "CC0000"
          ];
          gpu_temp = true;
          gpu_color = "2E9762";
          cpu_text = "CPU";
          cpu_stats = true;
          cpu_load_change = true;
          cpu_load_value = [
            50
            90
          ];
          cpu_load_color = [
            "FFFFFF"
            "FFAA7F"
            "CC0000"
          ];
          cpu_temp = true;
          cpu_color = "2E97CB";
          ram = true;
          ram_color = "C26693";
          fps = true;
          fps_limit_method = "late";
          toggle_fps_limit = "Shift_L+F1";
          fps_limit = 0;
          vsync = 4;
          fps_color_change = true;
          fps_color = [
            "B22222"
            "FDFD09"
            "39F900"
          ];
          fps_value = [
            30
            60
          ];
          output_folder = "${config.home.homeDirectory}/.local/share/mangohud";
          log_duration = 30;
          log_interval = 100;
          toggle_logging = "Shift_L+F2";
        };
      };

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

      programs.discord.enable = true;

      # This machine's system user is "djlechuck", unlike the "work" machine
      # where it's "vdebona". The ~/.ssh/config.d hosts (cloned from a shared
      # private repo, identical on both machines) mostly omit an explicit
      # User, relying on the system user matching the remote account
      # ("vdebona") - true on "work" but not here.
      #
      # Scoped to config.d only (not a blanket `Host *`): applies when the
      # typed name (%n) matches a config.d "Host" alias OR a "HostName" it
      # points to - the latter covers connecting by the real FQDN instead of
      # the alias (e.g. `ssh vm-umanit.uman-it.fr` instead of
      # `infra_vm-umanit`), which is otherwise invisible to this check.
      # [[:space:]]* tolerates these files' indented HostName/User lines.
      # Any host that already sets its own User keeps it, since Include is
      # read before this Match block.
      programs.ssh.settings."Match exec \"grep -qE '^[[:space:]]*Host(Name)?[[:space:]]+%n[[:space:]]*\$' ~/.ssh/config.d/*.conf\"".user =
        "vdebona";

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

  hardware.xone.enable = true;
}
