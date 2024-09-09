{
  description = "Buck2 project template supporting both nix-based GHC env and custom GHC HEAD";
  inputs = {
    nixpkgs.url = "github:MercuryTechnologies/nixpkgs/ghc962";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:matthewbauer/flake-compat/support-fetching-file-type-flakes";
      flake = false;
    };
    rust-overlay.url = "github:oxalica/rust-overlay";
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ rust-overlay.overlays.default ] ++ import ./toolchains/nix/overlays;
        config = {
          allowUnfree = true;
          allowBroken = true;
        };
      };

      toolchains = import toolchains/nix { inherit system; };

      inherit (toolchains.packages.${system}) ghcWithPackages haddock;

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
      ];

      macOS-security =
        # make `/usr/bin/security` available in `PATH`, which is needed for stack
        # on darwin which calls this binary to find certificates
        pkgs.writeScriptBin "security" ''exec /usr/bin/security "$@"'';
    in
    rec {
      packages = {
        inherit ghcWithPackages;
        buck2-update = pkgs.writeShellApplication {
          name = "buck2-update";
          runtimeInputs = with pkgs; [ curl jq nix-prefetch common-updater-scripts nix coreutils ];

          text = ''
            exec "$BASH" nix/overlays/buck2/update.sh
          '';
        };
      };

      devShells = rec {
        buck2 = buck2-nix;
        buck2-nix = pkgs.mkShellNoCC {
          name = "buck2-nix-shell";
          packages = buck2BuildInputs ++ [
            pkgs.buck2-source
            pkgs.nix
            pkgs.jq
          ];

          shellHook = ''
            export PS1="\n[buck2-nix:\w]$ \0"
          '';
        };
        buck2-ghcHEAD = pkgs.mkShell {
          name = "buck2-ghcHEAD-shell";
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
            export PS1="\n[buck2-ghcHEAD:\w]$ \0"
          '';
        };

      };
    });

  nixConfig.allow-import-from-derivation = true; # needed for cabal2nix

}
