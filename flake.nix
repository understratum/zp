{
  description = "Development shell for zp";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = function:
        nixpkgs.lib.genAttrs systems (system: function (import nixpkgs {
          inherit system;
        }));
      packageFor = pkgs: pkgs.stdenv.mkDerivation {
        pname = "zp";
        version = "0.3.1";
        src = self;
        nativeBuildInputs = [ pkgs.zig_0_16 ];
        buildPhase = "zig build -Doptimize=ReleaseSafe";
        installPhase = ''
          mkdir -p $out/bin
          cp zig-out/bin/zp $out/bin/zp
        '';
        meta.mainProgram = "zp";
      };
    in
    {
      packages = forAllSystems (pkgs: {
        default = packageFor pkgs;
        zp = packageFor pkgs;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${packageFor pkgs}/bin/zp";
        };
        zp = {
          type = "app";
          program = "${packageFor pkgs}/bin/zp";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.zig_0_16 ];
        };
      });
    };
}
