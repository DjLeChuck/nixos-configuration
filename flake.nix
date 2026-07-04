{
  description = "NixOS configuration - DjLeChuck";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    foundryvtt = {
      url = "github:djlechuck/nixos-foundryvtt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, foundryvtt, ... }: {
    nixosConfigurations = {
      # -------------------------------------------------------
      # VM VirtualBox - Home
      # -------------------------------------------------------
      vm-home = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit home-manager; };
        modules = [
          ./common/configuration.nix
          ./machines/vm-home/hardware-configuration.nix
          ./machines/vm-common/default.nix
          ./machines/vm-home/default.nix
          sops-nix.nixosModules.sops
          foundryvtt.nixosModules.default
          { networking.hostName = "vm-home"; }
        ];
      };

      # -------------------------------------------------------
      # VM VirtualBox - Work
      # -------------------------------------------------------
      vm-work = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit home-manager; };
        modules = [
          ./common/configuration.nix
          ./machines/vm-work/hardware-configuration.nix
          ./machines/vm-common/default.nix
          sops-nix.nixosModules.sops
          { networking.hostName = "vm-work"; }
        ];
      };

      # -------------------------------------------------------
      # Personal computer
      # -------------------------------------------------------
      home = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common/configuration.nix
          ./machines/home/hardware-configuration.nix
          ./machines/home/default.nix
          sops-nix.nixosModules.sops
          foundryvtt.nixosModules.default

          {
            boot.loader.grub = {
              enable = true;
              efiSupport = true;
              efiInstallAsRemovable = false;
              device = "nodev";
              useOSProber = true;
            };
            boot.loader.efi.canTouchEfiVariables = true;
            networking.hostName = "djlechuck-linux";
            system.stateVersion = "26.05";
          }

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bck";
            home-manager.users.djlechuck = import ./common/home.nix;
          }
        ];
      };

      # -------------------------------------------------------
      # Work computer
      # -------------------------------------------------------
      work = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common/configuration.nix
          ./machines/work/hardware-configuration.nix
          ./machines/work/default.nix
          sops-nix.nixosModules.sops
          foundryvtt.nixosModules.default

          {
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
            networking.hostName = "LIN-2025-1";
            system.stateVersion = "26.05";
          }

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bck";
            home-manager.users.vdebona = import ./common/home.nix;
          }
        ];
      };
    };
  };
}
