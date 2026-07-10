{
  description = "Unofficial NixOS integration for OpenLinkHub — Corsair iCUE LINK controller";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;
      inherit (nixpkgs) lib;

      # Strip dotfiles, .direnv, and result symlinks so that git index changes
      # or stale build outputs do not invalidate the check derivations.
      nixSrc = lib.cleanSourceWith {
        src = ./.;
        filter =
          path: _type:
          let
            baseName = baseNameOf (toString path);
          in
          !(lib.hasPrefix "." baseName) && baseName != "result";
      };
    in
    {

      # Intentional passthrough: consumers can override openlinkhub in their own
      # overlay without forking this flake. See README § "Overriding the package".
      overlays.default = _final: prev: {
        inherit (prev) openlinkhub;
      };

      packages.${system} = {
        inherit (pkgs) openlinkhub;
        default = pkgs.openlinkhub;
      };

      nixosModules.openlinkhub = import ./module.nix;
      nixosModules.default = self.nixosModules.openlinkhub;

      # nix fmt
      formatter.${system} = pkgs.nixfmt-tree;

      # nix flake check
      checks.${system} = {
        statix = pkgs.runCommand "check-statix" { buildInputs = [ pkgs.statix ]; } ''
          statix check ${nixSrc} && touch $out
        '';
        deadnix = pkgs.runCommand "check-deadnix" { buildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail ${nixSrc} && touch $out
        '';
        # nixfmt-tree is a wrapper around treefmt that pre-bakes nixfmt as the
        # formatter and injects its own treefmt.toml; --ci enables --no-cache and
        # --fail-on-change, which is the correct check mode.
        nixfmt = pkgs.runCommand "check-nixfmt" { buildInputs = [ pkgs.nixfmt-tree ]; } ''
          treefmt --ci --tree-root ${nixSrc} && touch $out
        '';

        # Evaluates the module options without real hardware or hardware-configuration.nix;
        # assertions are forced via builtins.seq to catch option-type mismatches early.
        module-eval =
          let
            eval = nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [ self.nixosModules.openlinkhub ];
            };
          in
          builtins.seq eval.config.assertions pkgs.emptyFile;
      };
    };
}
