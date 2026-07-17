# NixOS Configuration

My personal NixOS configuration, managed with [Flakes](https://wiki.nixos.org/wiki/Flakes) and [Home Manager](https://github.com/nix-community/home-manager).

## Overview

This repository contains a declarative, reproducible system configuration for all my machines. Everything - packages, services, desktop environment, dotfiles - is defined in Nix and version-controlled.

### Machines

| Machine   | Description                      | Boot               | GPU                        |
| --------- | -------------------------------- | ------------------ | -------------------------- |
| `home`    | Personal workstation             | systemd-boot / EFI | NVIDIA RTX 3080 Ti         |
| `work`    | Work laptop (Tuxedo)             | systemd-boot / EFI | Integrated (Tuxedo laptop) |
| `vm-home` | VirtualBox VM for testing `home` | GRUB / BIOS        | Virtual                    |
| `vm-work` | VirtualBox VM for testing `work` | GRUB / BIOS        | Virtual                    |

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

#### Private GitLab tools

`pkgs/private-tools.nix` fetches prebuilt CLI binaries from the company's
private GitLab. Neither the repo URLs nor the auth token are ever committed
in clear: URLs live in `common/variables.nix` (local-only, `skip-worktree`),
the token lives encrypted in `secrets/private-tools.yaml` (sops).

One-time setup:

```bash
# Create/edit the encrypted token (scope: read_api)
sops secrets/private-tools.yaml
# -> gitlab_tools_token: <PAT>
```

Fill in the real `privateTools` URLs/host in `common/variables.nix` (kept
local by `skip-worktree`, see `git ignored`).

`modules/private-tools.nix` feeds the decrypted token into `nix-daemon`'s own
systemd environment, since builds run through the daemon rather than the
interactive shell. That means on first rollout the daemon needs to pick up
the new `EnvironmentFile` _before_ the tool packages can build:

```bash
# 1) First switch: only wires the secret into nix-daemon's environment
sudo nixos-rebuild switch --flake .#home

# 2) Second switch: now nix-daemon has GITLAB_TOOLS_TOKEN, the fetchurl
#    derivations in pkgs/private-tools.nix can authenticate
sudo nixos-rebuild switch --flake .#home
```

To pin a real `sha256` for a tool, start with `pkgs.lib.fakeSha256`, let the
build fail, then copy the "got:" hash reported by Nix into `variables.nix`.
Repeat whenever a tool's URL/version changes.

#### Private SSH config.d

`~/.ssh/config.d` (included by `programs.ssh` in `common/home.nix` via
`Include ~/.ssh/config.d/*.conf`) is left unmanaged by Nix on purpose: its
content (internal hosts, IPs, work-specific aliases) lives in a private git
repo, not in this public repo. Same setup as the private GitLab tools above:
the repo path lives in `common/variables.nix` (local-only, `skip-worktree`),
the auth token lives encrypted in `secrets/ssh-config-private.yaml` (sops).

One-time setup:

```bash
# Create/edit the encrypted token (scope: read_repository)
sops secrets/ssh-config-private.yaml
# -> ssh-config-private-token: <PAT>
```

Fill in the real `sshConfigPrivate.repoPath` in `common/variables.nix` (kept
local by `skip-worktree`, see `git ignored`).

`modules/ssh-config-private.nix` decrypts the token for the interactive user
(unlike the GitLab tools token, this one doesn't need to reach nix-daemon).
`common/home.nix`'s `home.activation.cloneSshConfigPrivate` clones the repo
into `~/.ssh/config.d` over HTTPS the first time it runs, embedding the token
in the clone's remote URL so it persists in that repo's local `.git/config`.
As with the GitLab tools token, the very first switch may run before the
secret is decrypted - the activation script just skips and logs a message in
that case, so a second switch picks it up:

```bash
sudo nixos-rebuild switch --flake .#home
```

Afterwards, updating the content is a plain manual pull - no auto-pull on
every switch:

```bash
cd ~/.ssh/config.d && git pull
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
