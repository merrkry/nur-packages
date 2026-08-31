{ config, lib, ... }:

let
  cfg = config.programs.omarchy-shell;
in
{
  options.programs.omarchy-shell.enable = lib.mkEnableOption "PAM authentication for Omarchy Shell's lock screen";

  config = lib.mkIf cfg.enable {
    security.pam.services.omarchy-lock-password = { };
  };
}
