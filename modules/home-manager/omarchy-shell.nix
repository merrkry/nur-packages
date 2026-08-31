{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.omarchy-shell;
  jsonFormat = pkgs.formats.json { };
  defaultPackage = pkgs.callPackage ../../pkgs/omarchy-shell { };
in
{
  options.programs.omarchy-shell = {
    enable = lib.mkEnableOption "the Omarchy bar, notifications, idle service, and lock screen";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "Omarchy Shell package to use.";
    };

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = builtins.fromJSON (builtins.readFile ../../pkgs/omarchy-shell/shell.json);
      description = "Omarchy shell.json configuration.";
    };

    theme = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = "${cfg.package}/share/omarchy/theme";
      description = "Theme directory linked as the active Omarchy theme, or null to manage it separately.";
    };

    systemd.enable = lib.mkEnableOption "starting Omarchy Shell with the graphical session" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."omarchy/shell.json".source = jsonFormat.generate "omarchy-shell.json" cfg.settings;

    home.file = lib.mkIf (cfg.theme != null) {
      ".local/state/omarchy/current/theme".source = cfg.theme;
    };

    systemd.user.services.omarchy-shell = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "Omarchy Shell";
        Documentation = "https://github.com/basecamp/omarchy";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 1;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
