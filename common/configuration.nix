{ config, pkgs, ... }:

let
  gnomeExtensionNames = import ./gnome-extension-names.nix;
in
{
  imports = [
    ../modules/wifi-home.nix
  ];

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  networking.networkmanager.enable = true;

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

  programs.appimage.enable = true;

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
