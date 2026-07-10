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
      lib = nixpkgs.lib;

      # Filtre les fichiers non-Nix (.direnv, result, .git, etc.) pour éviter
      # des invalidations de cache inutiles dans les checks.
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

      # Passthrough intentionnel : les utilisateurs peuvent override openlinkhub ici
      # sans avoir à forker ce flake (ex: overrideAttrs pour patcher la source).
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
          statix check ${nixSrc} && touch $out
        '';
        deadnix = pkgs.runCommand "check-deadnix" { buildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail ${nixSrc} && touch $out
        '';
        nixfmt = pkgs.runCommand "check-nixfmt" { buildInputs = [ pkgs.nixfmt-tree ]; } ''
          nixfmt --check ${nixSrc}/*.nix && touch $out
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
