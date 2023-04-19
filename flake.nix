{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zls-flake.url = "github:zigtools/zls";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    
    zls-flake.inputs = {
      nixpkgs.follows = "nixpkgs";
      zig-overlay.follows = "zig-overlay";
      flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, zig-overlay, nixpkgs, flake-utils, zls-flake }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ zig-overlay.overlays.default ];
      };
      lib = pkgs.lib;
      zls = zls-flake.packages.${system}.zls;
    in rec {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.zigpkgs.master
          zls

          pkgs.gdb
          pkgs.valgrind
          pkgs.linuxPackages_latest.perf
          pkgs.perf-tools

          pkgs.git
          pkgs.pkg-config
          pkgs.gtk3
          pkgs.wine64
        ];

        LD_LIBRARY_PATH = "${lib.makeLibraryPath [
          pkgs.libGL
          pkgs.vulkan-loader
          pkgs.wayland
          pkgs.libxkbcommon
        ]}";
      };
  });
}
