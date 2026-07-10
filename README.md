# nix-openlinkhub

Unofficial NixOS flake for [OpenLinkHub](https://github.com/jurkovic-nikola/OpenLinkHub), an open-source daemon for Corsair iCUE LINK hubs, AIOs, and other supported HID/USB peripherals.

This flake lets you use it immediately in any NixOS configuration with flakes enabled.

---

## Prerequisites

- NixOS with flakes enabled (`experimental-features = nix-command flakes` in `nix.settings`)
- `x86_64-linux` system (the only architecture currently tested)

---

## Integration

### 1. Add the flake input

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    openlinkhub-flake = {
      url = "github:skelettor/nix-openlinkhub";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, openlinkhub-flake, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Pull in the overlay so the openlinkhub package is available
        { nixpkgs.overlays = [ openlinkhub-flake.overlays.default ]; }

        # Import the NixOS module
        openlinkhub-flake.nixosModules.openlinkhub

        # Your own configuration
        ./configuration.nix
      ];
    };
  };
}
```

Commit the generated `flake.lock` to version-control so every machine uses the exact same pinned revision.

### 2. Enable the service

```nix
# configuration.nix (or any module in your nixosConfigurations)
{
  services.hardware.openlinkhub.enable = true;
}
```

The daemon starts automatically and exposes a web UI at <http://127.0.0.1:27003>.

---

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `services.hardware.openlinkhub.enable` | `bool` | `false` | Enable the OpenLinkHub daemon. |
| `services.hardware.openlinkhub.package` | `package` | `pkgs.openlinkhub` | The OpenLinkHub package to use. Override to pin a specific version or apply patches. |

### Overriding the package

Use the overlay entry point to customise the package without forking the module:

```nix
{
  nixpkgs.overlays = [
    (final: prev: {
      openlinkhub = prev.openlinkhub.overrideAttrs (old: {
        # e.g. pin a different source revision
      });
    })
  ];
}
```

---

## Runtime details

- **Web UI:** `http://127.0.0.1:27003` by default. `listenAddress` and `listenPort` are editable in the UI; if you expose the UI on a non-loopback address, add the port to `networking.firewall.allowedTCPPorts` yourself.
- **State directory:** `/var/lib/openlinkhub/` — runtime config (`config.json`) and device database are persisted here and survive rebuilds. The `web/` and `static/` directories inside it are symlinks into the read-only Nix store; only the database and config are writable.
- **System user/group:** the daemon runs as `openlinkhub:openlinkhub`. Add your user to the `openlinkhub` group for direct device access outside the daemon.

---

## Known limitations

- **udev rules are required.** The module installs udev rules automatically via `services.udev.packages`. The daemon will not detect devices without them. A `nixos-rebuild switch` (or reboot) is needed after first installation for udev to pick up the new rules.
- **udev rule ownership patch.** The upstream rule sets `OWNER="openlinkhub"`, which requires root. This module rewrites it to `GROUP="openlinkhub"` so the daemon can run as an unprivileged system user. The net effect is the same: only members of the `openlinkhub` group have direct access to device nodes.
- **`uinput` for SCUF gamepad emulation is optional.** The shipped udev rule normally autoloads the `uinput` kernel module. If it is not loaded on your system, add it explicitly:
  ```nix
  boot.kernelModules = [ "uinput" ];
  ```
- **`x86_64-linux` only.** The flake is currently wired for `x86_64-linux`. AArch64 support depends on the upstream package supporting cross-compilation.

---

## CI / Contributing

CI runs `nix flake check` on every push and pull request (covers `statix`, `deadnix`, `nixfmt`, and module evaluation). A scheduled job watches for new upstream releases and opens a lock-update PR automatically.

To run the same checks locally:

```bash
nix flake check
```

**Tip:** The CI pipeline uses the [nix-community](https://nix-community.cachix.org) Cachix binary cache. Adding it to your Nix config speeds up evaluation:

```nix
nix.settings = {
  substituters = [ "https://nix-community.cachix.org" ];
  trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSDs=" ];
};
```

Maintainers: the automated lock-update PR job requires a `CI_BOT_TOKEN` secret (a PAT with `contents: write` and `pull-requests: write` on this repository). Without it, the job falls back silently — you can still run it manually via `workflow_dispatch`.
