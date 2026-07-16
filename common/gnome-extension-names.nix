# List of GNOME Shell extension attribute names (as exposed under `pkgs.gnomeExtensions`)
# installed/enabled on every machine.
#
# Single source of truth shared between:
#   - common/configuration.nix : installs the extension packages system-wide
#   - common/home.nix          : enables the extensions via dconf (enabled-extensions)
#
# Machine-specific extensions (e.g. hardware-dependent ones) don't belong here -
# set `custom.gnomeExtensionNames` instead (see ../modules/gnome-extensions.nix).
[
  "appindicator"
  "dash-to-dock"
  "no-overview"
  "quick-settings-audio-devices-hider"
  "quick-settings-audio-devices-renamer"
  "steal-my-focus-window"
]
