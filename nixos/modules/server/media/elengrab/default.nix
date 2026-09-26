{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server.elengrab;
  elengrab = pkgs.stdenvNoCC.mkDerivation {
    pname = "elengrab";
    version = "0.25.5";
    src = pkgs.fetchurl {
      url = "https://github.com/neosy/elengrab/releases/download/v0.25.5/elengrab-linux-amd64.tar.gz";
      hash = "sha256-NQo5RKoFnhf5PbHSpHV8gSKHjyINjOUhm9F5mve82eg=";
    };
    sourceRoot = ".";
    dontBuild = true;
    installPhase = "install -Dm755 elengrab-linux-amd64 $out/bin/elengrab";
  };
in
{
  options.server.elengrab.enable = lib.mkEnableOption "elengrab service";
  config = lib.mkIf cfg.enable {
    users.users.elengrab = {
      isSystemUser = true;
      group = "elengrab";
      home = "/var/lib/elengrab";
    };
    users.groups.elengrab = { };
    systemd.tmpfiles.rules = [ "d /var/lib/elengrab 0750 elengrab elengrab -" ];

    systemd.services.elengrab = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${elengrab}/bin/elengrab";
        Environment = [
          "ELENGRAB_ROOT_DIR=/var/lib/elengrab"
          "ELENGRAB_MODE=authenticated"
          "ELENGRAB_DOWNLOAD_WORKERS=1"
          "PATH=${
            lib.makeBinPath [
              pkgs.yt-dlp
              pkgs.ffmpeg
            ]
          }"
        ];
        User = "elengrab";
        Group = "elengrab";
        WorkingDirectory = "/var/lib/elengrab";
        Restart = "on-failure";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/elengrab" ];
      };
    };
  };
}
