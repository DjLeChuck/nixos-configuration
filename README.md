# NixOS Configuration

My personal NixOS configuration, managed with [Flakes](https://wiki.nixos.org/wiki/Flakes) and [Home Manager](https://github.com/nix-community/home-manager).

## Overview

This repository contains a declarative, reproducible system configuration for all my machines. Everything - packages, services, desktop environment, dotfiles - is defined in Nix and version-controlled.

### Machines

| Machine   | Description                      | Boot               | GPU                        |
| --------- | -------------------------------- | ------------------ | -------------------------- |
| `home`    | Personal workstation             | systemd-boot / EFI | NVIDIA RTX 3080 Ti         |
| `work`    | Work laptop (Tuxedo)             | systemd-boot / EFI | Integrated (Tuxedo laptop) |

### Structure

```
.
├── flake.nix                         # Entry point - inputs, flake-parts bootstrap
├── flake.lock                        # Pinned dependency versions
├── flake-modules/
│   ├── nixos-hosts.nix                # mkHost builder + nixosConfigurations
│   └── packages.nix                   # perSystem packages (private tools, GNOME extension)
├── common/
│   ├── configuration.nix             # Shared system config (packages, services, GNOME…)
│   ├── home.nix                      # Shared Home Manager config (git, fish, bash, ssh…)
│   └── dotfiles/
│       ├── fish_prompt.fish          # Custom fish prompt
│       └── fish_right_prompt.fish    # Custom fish right prompt (git + clock)
└── machines/
    ├── home/
    │   ├── hardware-configuration.nix
    │   └── default.nix               # Personal workstation-specific config
    └── work/
        ├── hardware-configuration.nix
        └── default.nix               # Work laptop-specific config (Tuxedo, LUKS…)
```

### Usage

#### Apply configuration

```bash
# Build and switch to a machine configuration
sudo nixos-rebuild switch --flake .#home

# Test without making it the default boot entry
sudo nixos-rebuild test --flake .#home

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

This whole feature is gated behind `privateTools.enable` in
`common/variables.nix` - a required key, always present (the committed
skeleton defaults it to `false`). A base system always builds and switches
fine with it off - no token, no URLs, no sops setup required. Only flip it
on once the steps below are done; until then `lock-excel`/`excel2jsonl` are
simply absent, with no error.

One-time setup, in order:

1. Make sure this machine's age key is a recipient for
   `secrets/private-tools.yaml` in `.sops.yaml` (see `make checklist
   HOST=<name>`), then create/edit the encrypted token (scope: `read_api`):

   ```bash
   sops secrets/private-tools.yaml
   # -> gitlab_tools_token: <PAT>
   ```

2. Fill in the real `privateTools` URLs/host in `common/variables.nix` (kept
   local by `skip-worktree`, see `git ignored`).

3. Set `privateTools.enable = true;` in that same local `common/variables.nix`.

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

To pin a real `sha256` for a tool, start with `lib.fakeHash` (the value
already used as a placeholder in the committed `variables.nix` skeleton -
`fakeSha256` is the older, deprecated name for the same thing), let the
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

#### Claude Code data sync (pCloud)

`~/.claude/{projects,plans,CLAUDE.md,statusline.py}` (conversations, plans,
per-project memory, global preferences, status line script) sync between
`home` and `work` through a shared pCloud remote, via the `claude-sync`
script (`common/home.nix`) wired to
Claude Code's `SessionStart`/`SessionEnd` hooks plus a 20-minute
`claude-sync-push` timer as a crash safety net. It's a plain `rclone copy
--update` in each direction - additive only, never deletes - which is safe
because the two machines are never used at the same time. A desktop
notification (`libnotify`) fires whenever a sync actually transfers a file,
and a critical one on a real failure (a missing remote path on a first-ever
sync doesn't count as one) - a no-op sync stays silent.

`~/.claude/projects/<slug>` is named from a literal transform of the
project's absolute path, so a project living under `$HOME` (this
`nixos-config` checkout, or any future one) gets a different slug on `home`
(`djlechuck`) and `work` (`vdebona`) and would never merge. `claude-sync`
re-homes any such project to a machine-independent slug (`-HOMESYNC...`) on
push and back to the local slug on pull, so it merges the same way projects
under the shared `/srv/development` path already do - no per-project
configuration needed.

The rclone remote config (`~/.config/rclone/rclone.conf`, holding the pCloud
OAuth token) is deployed by `modules/rclone-pcloud.nix` from a single sops
secret shared by both machines, so the OAuth flow only has to happen once,
not per machine:

```bash
# 1) Anywhere with a browser: authorize once and capture the resulting
#    rclone.conf ([pcloud] section, OAuth token included). If this machine
#    hasn't switched with `rclone` in home.packages yet, run it ephemerally
#    instead - it still writes to the default ~/.config/rclone/rclone.conf:
#    nix run nixpkgs#rclone -- config
rclone config
# -> n) New remote -> name "pcloud" -> type "pcloud" -> follow the browser flow

# 2) Encrypt that file's content into the repo
sops secrets/rclone-pcloud.conf
# -> paste the full rclone.conf content, save

# 3) Roll out to each machine
sudo nixos-rebuild switch --flake .#home
sudo nixos-rebuild switch --flake .#work
```

As with the other sops-backed secrets above, the very first switch on a
machine may run before the secret is decrypted - `claude-sync` will just fail
silently (best-effort) until the next switch picks it up.

Bootstrap the remote itself once, from whichever machine already has
`~/.claude` data:

```bash
claude-sync push   # seed pCloud from this machine
claude-sync pull   # on the other machine, once its rclone.conf is deployed
```

Finally, add the hooks to `~/.claude/settings.json` on each machine (not
managed by Nix - Claude Code writes to that file itself). `${CLAUDE_PROJECT_DIR}`
is interpolated by Claude Code into the command before it runs (see the
[hooks reference](https://code.claude.com/docs/en/hooks.md)); passing it as
the 2nd arg scopes the sync to that one project instead of every project
under `~/.claude/projects` - confirmed empirically to be the exact directory
`claude-sync` derives the project's slug from. A scoped sync still costs
~2.3s (fixed per-`rclone`-invocation overhead - auth/TLS, not file count), so
both hooks background it via `setsid ... &` instead of blocking session
start/stop on it. `SessionStart`'s pull is safe to background outright - a
session doesn't need its own history pulled before it can be used, and it
self-corrects within a couple seconds. `SessionEnd`'s push relies on `setsid`
actually detaching the process from the terminal session Claude Code is
about to tear down - a bare trailing `&` alone wouldn't survive that:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "setsid claude-sync pull \"${CLAUDE_PROJECT_DIR}\" < /dev/null > /dev/null 2>&1 &", "timeout": 30 }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "setsid claude-sync push \"${CLAUDE_PROJECT_DIR}\" < /dev/null > /dev/null 2>&1 &", "timeout": 30 }] }
    ]
  }
}
```

Since the sync now runs detached, the desktop notification (see above) is
the only signal that it happened at all - there's nothing left to wait on.

#### Update dependencies

```bash
# Update all flake inputs (nixpkgs, home-manager)
nix flake update

# Update a specific input
nix flake update nixpkgs

# Then rebuild
sudo nixos-rebuild switch --flake .#home
```

#### Search for packages or options

```bash
# Search for a package
nix search nixpkgs firefox

# Or use the web interface
# Packages: https://search.nixos.org/packages
# Options:  https://search.nixos.org/options
```
