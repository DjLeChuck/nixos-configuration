# NixOS Configuration

My personal NixOS configuration, managed with [Flakes](https://wiki.nixos.org/wiki/Flakes) and [Home Manager](https://github.com/nix-community/home-manager).

## Overview

This repository contains a declarative, reproducible system configuration for all my machines. Everything - packages, services, desktop environment, dotfiles - is defined in Nix and version-controlled.

### Machines

| Machine   | Description               | Boot               | GPU                |
| --------- | ------------------------- | ------------------ | ------------------ |
| `vm-test` | VirtualBox VM for testing | GRUB / BIOS        | Virtual            |
| `home`    | Personal workstation      | systemd-boot / EFI | NVIDIA RTX 3080 Ti |

### Structure

```
.
├── flake.nix                         # Entry point - inputs & machine definitions
├── flake.lock                        # Pinned dependency versions
├── common/
│   ├── configuration.nix             # Shared system config (packages, services, GNOME…)
│   ├── home.nix                      # Shared Home Manager config (git, fish, bash, ssh…)
│   └── dotfiles/
│       ├── fish_prompt.fish          # Custom fish prompt
│       └── fish_right_prompt.fish    # Custom fish right prompt (git + clock)
└── machines/
    ├── vm-test/
    │   ├── hardware-configuration.nix
    │   └── default.nix               # VM-specific config
    └── home/
        ├── hardware-configuration.nix
        └── default.nix               # Personal workstation-specific config (NVIDIA, VirtualBox…)
```

### Usage

#### Apply configuration

```bash
# Build and switch to a machine configuration
sudo nixos-rebuild switch --flake .#vm-test
sudo nixos-rebuild switch --flake .#home

# Test without making it the default boot entry
sudo nixos-rebuild test --flake .#vm-test

# Rollback to the previous generation
sudo nixos-rebuild switch --rollback
```

#### GPG key

`modules/gpg.nix` only decrypts the sops-encrypted private key to `/run/secrets/gpg-private-key` (owned by the target user) - it does **not** import it automatically.

To (re-)encrypt the key after generating/rotating it, run this yourself so the plaintext key never goes through an agent/session other than your own:

```bash
gpg --export-secret-keys --armor <KEY_ID> > secrets/gpg/private-key.asc
sops --encrypt --in-place secrets/gpg/private-key.asc
```

After each `nixos-rebuild switch` (or on a freshly provisioned machine), import the key into the keyring manually, once:

```bash
gpg --batch --import /run/secrets/gpg-private-key
```

#### Update dependencies

```bash
# Update all flake inputs (nixpkgs, home-manager)
nix flake update

# Update a specific input
nix flake update nixpkgs

# Then rebuild
sudo nixos-rebuild switch --flake .#vm-test
```

#### Search for packages or options

```bash
# Search for a package
nix search nixpkgs firefox

# Or use the web interface
# Packages: https://search.nixos.org/packages
# Options:  https://search.nixos.org/options
```
