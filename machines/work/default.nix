{ config, pkgs, claude-code, ... }:

{
  imports = [
    ../../modules/ansible-vault-passwords.nix
    ../../modules/composer-auth.nix
    ../../modules/ssh-config-private.nix
    ../../modules/user-password.nix
    ../../modules/vpn-work.nix
    ../../modules/vpn-home.nix
  ];

  custom.ansibleVaultPasswords.user = "vdebona";
  custom.composerAuth.user = "vdebona";
  custom.sshConfigPrivate.user = "vdebona";
  custom.userPassword.user = "vdebona";

  # Graphical splash covering the LUKS unlock prompt (like Ubuntu), instead
  # of it appearing mid-scroll in the kernel/systemd boot log. The legacy
  # (non-systemd) initrd's LUKS prompt is a plain `read`, not wired to
  # Plymouth - the systemd initrd routes it through systemd-ask-password,
  # which Plymouth hooks into natively.
  boot.initrd.systemd.enable = true;
  boot.plymouth.enable = true;

  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [ "quiet" "udev.log_level=3" "rd.udev.log_level=3" ];

  # Every generation shares the same systemd-boot menu title ("NixOS"), so
  # systemd-boot disambiguates entries by appending system.nixos.label
  # (a verbose release+revision string by default) - shorten it instead.
  system.nixos.label = "work";
  boot.loader.systemd-boot.configurationLimit = 10;

  nixpkgs.overlays = [ claude-code.overlays.default ];

  hardware.tuxedo-rs = {
    enable = true;
    tailor-gui.enable = true;
  };

  hardware.tuxedo-drivers.settings.fn-lock = false;

  # HDMI/DP outputs are wired directly to the Nvidia dGPU (nouveau barely
  # modesets it, giving a black screen with only the cursor visible on any
  # external monitor). Use the proprietary driver with PRIME "sync" instead
  # of "offload": offload assumes the iGPU drives every physical port, which
  # isn't the case here, so the dGPU has to stay on and drive its own ports.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true; # Ada Lovelace (RTX 40xx mobile) supports the open kernel modules
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = true;

    prime = {
      sync.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # The keyboard's RGB controller (ITE8291) runs its own erratic per-key demo
  # effect until software explicitly overrides it - tailord's active profile has
  # "leds": [] so nothing ever does, and a udev rule that only sets "brightness"
  # doesn't stick (see community fix in tuxedocomputers/tuxedo-keyboard#204,
  # which writes both "multi_intensity" and "brightness" per key). Force both off
  # directly via sysfs in a oneshot service instead.
  systemd.services.disable-kbd-rgb-backlight = {
    description = "Turn off the keyboard RGB backlight LEDs";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for dev in /sys/class/leds/rgb:kbd_backlight*; do
        echo "0 0 0" > "$dev/multi_intensity" 2>/dev/null || true
        echo 0 > "$dev/brightness" 2>/dev/null || true
      done
    '';
  };

  users.users.vdebona = {
    isNormalUser = true;
    description = "Vivien";
    extraGroups = [ "networkmanager" "wheel" "docker" "foundryvtt" "foundryvtt-control" ];
    shell = pkgs.fish;
  };

  services.foundryvtt-instances = {
    v14.port = 30014;
  };
  services.foundryvtt-gnome-extension.enable = true;

  home-manager.users.vdebona =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        pkgs.claude-code
      ];

      dconf.settings."org/gnome/desktop/peripherals/touchpad".natural-scroll = false;

      # networking.hostName ("LIN-2025-1") doesn't match this flake's
      # nixosConfigurations attribute name ("work"), so `nh os` can't infer
      # it automatically — pin it explicitly.
      programs.fish.interactiveShellInit = ''
        set -gx NH_OS_FLAKE "$NIXOS_CONFIG_DIR#work"
      '';
    };
}
