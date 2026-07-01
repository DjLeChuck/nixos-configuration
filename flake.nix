{
  description = "NixOS configuration - DjLeChuck";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
    nixosConfigurations = {
      # -------------------------------------------------------
      # Test VM
      # -------------------------------------------------------
      vm-test = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common/configuration.nix
          ./machines/vm-test/hardware-configuration.nix

          {
            boot.loader.grub.enable = true;
            boot.loader.grub.device = "/dev/sda";
            networking.hostName = "djlechuck-nix";
            system.stateVersion = "26.05";

            users.users.djlechuck.extraGroups = [ "vboxsf" ];
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
      # Real computer
      # -------------------------------------------------------
      home = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common/configuration.nix
          ./machines/home/hardware-configuration.nix
          ./machines/home/default.nix

          {
            boot.loader.systemd-boot.enable = true;
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
    };
  };
}

