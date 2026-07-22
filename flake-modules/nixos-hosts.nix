{ inputs, self, ... }:

let
  inherit (inputs) nixpkgs home-manager sops-nix foundryvtt claude-code toggl-redmine;

  # Single place where every host's sops-nix / foundryvtt / home-manager
  # wiring happens - each host below only states what actually differs.
  mkHost =
    { hostName
    , bootloader
    , modules ? [ ]
    , homeUser ? null
    , withFoundry ? true
    , stateVersion ? "26.05"
    }:
    nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit self claude-code toggl-redmine; };
      # Machine-specific modules are merged before the common home-manager
      # wiring below, same as the pre-flake-parts module order, so a host's
      # own home-manager.users.<user> block (e.g. gaming packages) is merged
      # ahead of common/home.nix's.
      modules = [
        ../common/configuration.nix
      ]
      ++ modules
      ++ [ sops-nix.nixosModules.sops ]
      ++ nixpkgs.lib.optional withFoundry foundryvtt.nixosModules.default
      ++ [
        { networking.hostName = hostName; system.stateVersion = stateVersion; }
        bootloader
        home-manager.nixosModules.home-manager
      ]
      ++ nixpkgs.lib.optional (homeUser != null) {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bck";
        home-manager.extraSpecialArgs = { inherit toggl-redmine self; };
        home-manager.users.${homeUser} = import ../common/home.nix;
      };
    };
in
{
  flake.nixosConfigurations = {
    # VirtualBox VM mirroring `home`
    vm-home = mkHost {
      hostName = "vm-home";
      homeUser = "djlechuck";
      bootloader = {
        boot.loader.grub.enable = true;
        boot.loader.grub.device = "/dev/sda";
      };
      modules = [
        ../machines/vm-home/hardware-configuration.nix
        ../machines/vm-common/default.nix
        ../machines/vm-home/default.nix
      ];
    };

    # VirtualBox VM mirroring `work`
    vm-work = mkHost {
      hostName = "vm-work";
      homeUser = "djlechuck";
      withFoundry = false;
      bootloader = {
        boot.loader.grub.enable = true;
        boot.loader.grub.device = "/dev/sda";
      };
      modules = [
        ../machines/vm-work/hardware-configuration.nix
        ../machines/vm-common/default.nix
      ];
    };

    # Personal workstation
    home = mkHost {
      hostName = "djlechuck-linux";
      homeUser = "djlechuck";
      bootloader = {
        boot.loader.grub = {
          enable = true;
          efiSupport = true;
          efiInstallAsRemovable = false;
          device = "nodev";
          useOSProber = true;
          # Native 4K resolution makes GRUB's fixed-size font tiny; a
          # lower resolution keeps text readable (upscaled by the panel).
          gfxmodeEfi = "1920x1080;auto";
        };
        boot.loader.efi.canTouchEfiVariables = true;
      };
      modules = [
        ../machines/home/hardware-configuration.nix
        ../machines/home/default.nix
      ];
    };

    # Work laptop
    work = mkHost {
      hostName = "LIN-2025-1";
      homeUser = "vdebona";
      bootloader = {
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;
      };
      modules = [
        ../machines/work/hardware-configuration.nix
        ../machines/work/default.nix
      ];
    };
  };
}
