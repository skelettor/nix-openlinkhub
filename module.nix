{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hardware.openlinkhub;

  # Upstream sets OWNER="openlinkhub" in the udev rule, which requires the daemon
  # to run as root to take ownership of device nodes. We replace it with
  # GROUP="openlinkhub" so the daemon can run as an unprivileged system user.
  udevRulesPkg = pkgs.runCommand "openlinkhub-udev-rules" { } ''
    install -Dm 644 \
      ${cfg.package}/etc/udev/rules.d/99-openlinkhub.rules \
      $out/lib/udev/rules.d/99-openlinkhub.rules
    substituteInPlace $out/lib/udev/rules.d/99-openlinkhub.rules \
      --replace-fail 'OWNER="openlinkhub"' 'GROUP="openlinkhub"'
  '';
in
{
  options.services.hardware.openlinkhub = {
    enable = lib.mkEnableOption ''
      OpenLinkHub, an open-source controller daemon for Corsair iCUE LINK
      hubs, AIOs and other supported HID/USB peripherals.

      The daemon exposes a local web UI on `http://127.0.0.1:27003` by
      default. Both `listenAddress` and `listenPort` are configurable in
      `/var/lib/openlinkhub/config.json` via the web UI; if you expose the
      UI on a non-loopback address, open the corresponding port in
      `networking.firewall.allowedTCPPorts` yourself.

      All runtime configuration is owned by the daemon and persisted in
      `/var/lib/openlinkhub/config.json`, which is rewritten whenever
      settings change in the web UI. No declarative configuration options
      are provided; edit settings through the UI or by stopping the service
      and editing the JSON file directly.

      Device presets, LCD images and language files are seeded from the
      package into `/var/lib/openlinkhub/database/` on first start and are
      preserved across rebuilds.

      SCUF gamepad emulation requires the `uinput` kernel module, which is
      normally autoloaded on access via the shipped udev rule. If not, set
      `boot.kernelModules = [ "uinput" ]`.

      Users who need direct device access outside the daemon (e.g. for
      debugging) can be added to the `openlinkhub` group
    '';

    package = lib.mkPackageOption pkgs "openlinkhub" { };
  };

  config = lib.mkIf cfg.enable {
    users.users.openlinkhub = {
      isSystemUser = true;
      group = "openlinkhub";
      description = "OpenLinkHub daemon user";
    };
    users.groups.openlinkhub = { };

    services.udev.packages = [ udevRulesPkg ];

    systemd.services.openlinkhub = {
      description = "OpenLinkHub — Corsair iCUE LINK / AIO / Hub controller";
      wantedBy = [ "multi-user.target" ];
      # systemd-udev-settle ensures udev has finished processing events before the
      # daemon starts. Restart=always handles the residual race on first boot.
      after = [
        "network.target"
        "systemd-udev-settle.service"
      ];
      wants = [ "systemd-udev-settle.service" ];

      preStart = ''
        # web/ and static/ live in the read-only store; symlink them into the
        # writable StateDirectory so the daemon can serve them at runtime.
        ln -sfnT ${cfg.package}/opt/OpenLinkHub/web web
        ln -sfnT ${cfg.package}/opt/OpenLinkHub/static static
        mkdir -p database
        # Seed the database on first start. -n (no-clobber) preserves user data
        # (device profiles, settings) on subsequent restarts and rebuilds.
        cp -rn --no-preserve=mode,ownership \
          ${cfg.package}/opt/OpenLinkHub/database/. database/
        chmod -R u+w database
      '';

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        WorkingDirectory = "/var/lib/openlinkhub";
        StateDirectory = "openlinkhub";
        StateDirectoryMode = "0750";
        User = "openlinkhub";
        Group = "openlinkhub";
        SupplementaryGroups = [ "input" ];
        Restart = "always";
        RestartSec = "5s";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        MemoryDenyWriteExecute = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        CapabilityBoundingSet = [ "" ];
        AmbientCapabilities = [ "" ];
        DevicePolicy = "closed";
        DeviceAllow = [
          "char-hidraw rw"
          "char-usb_device rw"
          "/dev/uinput rw"
        ];
        UMask = "0027";
      };
    };
  };

  meta.maintainers = [ ];
}
