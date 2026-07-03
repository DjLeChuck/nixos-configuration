{
  imports = [ ../../modules/vpn-work.nix ];

  users.users.djlechuck.extraGroups = [ "foundryvtt" ];

  services.foundryvtt-instances.v14.port = 30014;
}
