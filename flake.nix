{
  description = "Buck2 project template supporting both nix-based GHC env and custom GHC HEAD";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils/v1.0.0";

    # NOTE: The buck2 tool is based on the upstream version with a few custom patches, and thus need
    # to be compiled. Since it needs a specific version of Rust nightly compiler, we use a specific
    # commit. We will reconcile the fenix version with other Rust-based tools later.
    fenix = {
      url = "github:nix-community/fenix/9d17341a4f227fe15a0bca44655736b3808e6a03";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays =
          [ inputs.fenix.overlays.default
            (self: super:
                { buck2-source = super.callPackage ./nix/packages/buck2-source {};
                }
            )
          ];
        config = {
          allowUnfree = true;
          allowBroken = true;
        };
      };

      buck2BuildInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.cacert
        pkgs.gnused
        pkgs.git
        pkgs.nix
        pkgs.openssh
      ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
        pkgs.stdenv.cc.bintools
        pkgs.darwin.cctools
        pkgs.darwin.apple_sdk.frameworks.Security
        pkgs.darwin.apple_sdk.frameworks.CoreFoundation
        pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
      ];

    in
    rec {
      devShells = rec {
        default = buck2;
        buck2 = pkgs.mkShell {
          name = "buck2-shell";
          packages = buck2BuildInputs ++ [
            pkgs.buck2-source
            pkgs.nix
            pkgs.jq
            # REMOVE LATER
            pkgs.alex
          ];
          # GHC in invokes Nix cc, cc-wrapper invokes mktemp from $PATH. Also GHC invokes otool and
          # install_name_tool from $PATH on Darwin.
          GHC_PATH = pkgs.lib.makeSearchPath "bin" ([ pkgs.coreutils ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.stdenv.cc.bintools
            pkgs.darwin.cctools
          ]);

          shellHook = ''
            export PS1="\n[buck2:\w]$ \0"
          '';
        };

      };
    });

  nixConfig.allow-import-from-derivation = true; # needed for cabal2nix

}
