{ config, lib, ... }:

let
  cfg = config.custom.composerAuth;
  variables = import ../common/variables.nix;
in
{
  options.custom.composerAuth.user = lib.mkOption {
    type = lib.types.str;
    description = "User who owns the generated Composer auth.json (GitLab + GitHub tokens).";
  };

  config.sops.secrets = {
    "composer_gitlab_token" = {
      sopsFile = ../secrets/composer-auth.yaml;
    };
    "composer_github_token" = {
      sopsFile = ../secrets/composer-auth.yaml;
    };
  };

  config.sops.templates."composer-auth-json" = {
    content = builtins.toJSON {
      gitlab-token = {
        "${variables.privateTools.gitlabHost}" = config.sops.placeholder."composer_gitlab_token";
      };
      github-oauth = {
        "github.com" = config.sops.placeholder."composer_github_token";
      };
    };
    path = "/home/${cfg.user}/.config/composer/auth.json";
    owner = cfg.user;
    mode = "0400";
  };
}
