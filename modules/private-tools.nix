{ config, ... }:

{
  sops.secrets."gitlab_tools_token" = {
    sopsFile = ../secrets/private-tools.yaml;
  };

  sops.templates."gitlab-tools-env".content = ''
    GITLAB_TOOLS_TOKEN=${config.sops.placeholder."gitlab_tools_token"}
  '';

  # Fixed-output derivations authenticated via `netrcImpureEnvVars` read
  # impure env vars from the builder process, i.e. nix-daemon itself (builds
  # run through the multi-user daemon, not the interactive shell that ran
  # `nixos-rebuild switch`). Feeding the token here makes it available to any
  # such derivation without a wrapper script, and it never touches the store.
  systemd.services.nix-daemon.serviceConfig.EnvironmentFile = [
    config.sops.templates."gitlab-tools-env".path
  ];
}
