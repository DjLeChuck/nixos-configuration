{ config, lib, ... }:

let
  cfg = config.custom.claudeSync;
  secretPath = name: "/home/${cfg.user}/.config/claude-sync-${name}";
  userSecret = name: {
    sopsFile = ../secrets/common.yaml;
    path = secretPath name;
    owner = cfg.user;
    mode = "0400";
  };
in
{
  options.custom.claudeSync.user = lib.mkOption {
    type = lib.types.str;
    description = "User who owns the deployed claude-sync WebDAV URL and app password.";
  };

  # Both are read at runtime by claude-sync (services.claude-sync in
  # common/home.nix): the URL is a secret too, so it must not be baked into the
  # package, which would put it in the world-readable Nix store.
  config.sops.secrets = {
    "claude-sync/webdav-url" = userSecret "webdav-url";
    "claude-sync/webdav-password" = userSecret "webdav-password";
  };
}
