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
      # VM VirtualBox - Home
      # -------------------------------------------------------
      vm-home = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit home-manager; };
        modules = [
          ./common/configuration.nix
          ./machines/vm-home/hardware-configuration.nix
          ./machines/vm-common/default.nix
          { networking.hostName = "djlechuck-vm-home"; }
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
          { networking.hostName = "djlechuck-vm-work"; }
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
