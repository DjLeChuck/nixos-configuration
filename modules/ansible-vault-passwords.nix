{ config, lib, ... }:

let
  cfg = config.custom.ansibleVaultPasswords;
in
{
  options.custom.ansibleVaultPasswords.user = lib.mkOption {
    type = lib.types.str;
    description = "User who owns the decrypted Ansible vault password files in their home directory.";
  };

  config.sops.secrets = {
    "ansible-weblate-gitlab-vault-password" = {
      sopsFile = ../secrets/ansible-vault-passwords.yaml;
      owner = cfg.user;
      path = "/home/${cfg.user}/.ansible-weblate-gitlab-vault-password";
    };
    "ansible2-vault-password" = {
      sopsFile = ../secrets/ansible-vault-passwords.yaml;
      owner = cfg.user;
      path = "/home/${cfg.user}/.ansible2-vault-password";
    };
    "deploy-ansible-vault-password" = {
      sopsFile = ../secrets/ansible-vault-passwords.yaml;
      owner = cfg.user;
      path = "/home/${cfg.user}/.deploy-ansible-vault-password";
    };
  };
}
