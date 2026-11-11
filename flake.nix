{
  description = "Nix packaging for impeccable (design skill for AI coding agents) by Paul Bakaus";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Апстрим не флейк и не вендорится: обновление = `nix flake update impeccable-src`.
    impeccable-src = {
      url = "github:pbakaus/impeccable";
      flake = false;
    };

    # Нужен только чтобы проверить eval модуля в checks.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      impeccable-src,
      home-manager,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        # darwin собирается по тем же правилам, но здесь не проверялось.
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          impeccable = pkgs.callPackage ./nix/engine.nix { src = impeccable-src; };
          impeccable-skill = pkgs.callPackage ./nix/skill.nix {
            inherit impeccable;
            src = impeccable-src;
          };
        in
        {
          inherit impeccable impeccable-skill;
          default = impeccable-skill;
        }
      );

      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system}) impeccable impeccable-skill;
      };

      homeManagerModules.default = import ./nix/hm-module.nix self;

      checks = forAllSystems (
        system:
        import ./nix/checks.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit self system home-manager;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
