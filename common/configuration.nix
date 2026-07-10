{ config, pkgs, ... }:

let
  gnomeExtensionNames = import ./gnome-extension-names.nix;
  openvpn3SwitcherExtension = import ../gnome-extensions/openvpn3-switcher { inherit pkgs; };
  variables = import ./variables.nix;
  privateTools = import ../pkgs/private-tools.nix { inherit pkgs variables; };
in
{
  imports = [
    ../modules/fhs-bin-symlinks.nix
    ../modules/private-tools.nix
    ../modules/wifi-home.nix
  ];

  nixpkgs.overlays = [
    (import ../overlays/symfony-cli-php-reload-fix.nix)
  ];

  # Lets generically-linked prebuilt Linux binaries run on NixOS (e.g. the
  # actual node/yarn runtimes Volta downloads at "volta install" time - the
  # `volta`/`node`/`yarn` shims themselves are fine, but what they exec into
  # isn't a Nix-built binary and expects a standard FHS dynamic linker).
  programs.nix-ld.enable = true;

  # Team tooling (scripts, git hooks, IDE run configs) hardcodes these paths.
  custom.fhsBinSymlinks = {
    "/usr/local/bin/lock-excel" = "${privateTools.lock-excel}/bin/lock-excel";
    "/usr/local/bin/excel2jsonl" = "${privateTools.excel2jsonl}/bin/excel2jsonl";
    "/usr/bin/pngquant" = "${pkgs.pngquant}/bin/pngquant";
    "/usr/bin/jpegoptim" = "${pkgs.jpegoptim}/bin/jpegoptim";
    "/usr/bin/cwebp" = "${pkgs.libwebp}/bin/cwebp";
    "/usr/local/bin/wkhtmltopdf" = "${pkgs.wkhtmltopdf}/bin/wkhtmltopdf";
    "/bin/bash" = "${pkgs.bashInteractive}/bin/bash";
  };

  # Automatic weekly GC instead of manually deciding when it's worth it -
  # keeps 30 days of rollback-able generations, purges everything older.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  networking.networkmanager.enable = true;
  services.resolved.enable = true;

  # Keep hibernation/suspend-then-hibernate disabled as a safety net on hosts with
  # swap. Not the cause of GPU freezes on resume from plain suspend on `home` — see
  # hardware.nvidia.powerManagement in machines/home/default.nix for that fix.
  systemd.sleep.settings.Sleep = {
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
    AllowHybridSleep = false;
  };

  time.timeZone = "Europe/Paris";

  i18n.defaultLocale = "fr_FR.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };

  services.xserver.xkb = {
    layout = "fr";
    variant = "oss";
  };

  console.keyMap = "fr";

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.gnome.gcr-ssh-agent.enable = false;

  environment.gnome.excludePackages = with pkgs; [
    decibels
    epiphany
    geary
    gnome-calendar
    gnome-connections
    gnome-contacts
    gnome-maps
    gnome-music
    gnome-tour
    gnome-weather
    showtime
    snapshot
    yelp
  ];

  environment.systemPackages =
    (map (name: pkgs.gnomeExtensions.${name}) gnomeExtensionNames)
    ++ [ openvpn3SwitcherExtension ]
    ++ (with pkgs; [
      dconf-editor
      docker-compose
      file
      gcc
      gnome-tweaks
      gnumake
      python3
      python3Packages.pip
      sops
      ssh-to-age
      unzip
      wget
      zip
    ]);

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.bash = {
    completion.enable = true;
    enableLsColors = true;
  };

  programs.chromium = {
    enable = true;

    extensions = [
      "miefikpgahefdbcgoiicnmpbeeomffld" # Blackfire
      "hmeobnfnfcmdkdcmlblgagmfpfboieaf" # Ctrl Wallet
      "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
      "mdemppnhjflbejfbnlddahjbpdbeejnn" # Tamper Dev
      "oejgccbfbmkkpaidnkphaiaecficdnfn" # Toggle Track
      "eadndfjplgieldjbigjakmdgkmoaaaoc" # Xdebug Helper
    ];
  };

  programs.firefox = {
    enable = true;
    languagePacks = [ "fr" ];
  };

  programs.fish = {
    enable = true;
    vendor.completions.enable = true;
    vendor.config.enable = true;
    vendor.functions.enable = true;
  };

  programs.htop.enable = true;
  programs.less.enable = true;
  programs.nh.enable = true;

  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  programs.xwayland.enable = true;

  virtualisation.docker.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
      AllowUsers = [ "djlechuck" ];
    };
  };

  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # cups-browsed doesn't exit cleanly on SIGTERM (known cups-filters
  # behavior), so systemd waits the full default 90s TimeoutStopSec before
  # SIGKILLing it on every shutdown/reboot. Shorten it instead of disabling
  # network printer discovery.
  systemd.services.cups-browsed.serviceConfig.TimeoutStopSec = "5s";

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  nixpkgs.config.allowUnfree = true;

  # https://github.com/nixos/nixpkgs/issues/526914
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    liberation_ttf
  ];
}
