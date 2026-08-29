# Exposes the nixpkgs-unstable flake input as `pkgs.unstable`, so individual
# packages can opt into the unstable channel (e.g. `pkgs.unstable.symfony-cli`
# in common/home.nix) without moving the whole system off the pinned stable
# nixpkgs. To pull another package from unstable later, just reference it as
# `unstable.<name>` wherever it's used - no changes needed here.
{ nixpkgs-unstable }:
final: prev: {
  unstable = import nixpkgs-unstable {
    system = final.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
}
