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
      src = ./.;
    in
    {

      overlays.default = _final: prev: {
        # openlinkhub = prev.openlinkhub.overrideAttrs (old: { ... });

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
          statix check ${src} && touch $out
        '';
        deadnix = pkgs.runCommand "check-deadnix" { buildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail ${src} && touch $out
        '';

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
