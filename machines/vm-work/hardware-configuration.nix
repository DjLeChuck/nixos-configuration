# PLACEHOLDER - Replace this file with the output of:
#
# nixos-generate-config --show-hardware-config
#
# Run this command in the work VirtualBox VM and paste the result here.
# The UUID below belongs to vm-home and will NOT match the work disk.
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ ];

  boot.initrd.availableKernelModules = [ "ata_piix" "ohci_pci" "ehci_pci" "ahci" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/856989b6-1c7e-43bf-a378-fb4032763bb5";
      fsType = "ext4";
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  virtualisation.virtualbox.guest.enable = true;
}
