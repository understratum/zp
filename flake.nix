{
  description = "zp";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}:
    nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"] (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      packages.default = pkgs.stdenv.mkDerivation {
        pname = "zp";
        version = "0.3.1";
        src = ./.;
        nativeBuildInputs = [pkgs.zig_0_16];
        buildPhase = "zig build -Doptimize=ReleaseSafe";
        installPhase = ''
          mkdir -p $out/bin
          cp zig-out/bin/zp $out/bin/
        '';
      };
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          zig_0_16
        ];
      };
    });
}
