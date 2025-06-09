{
  description = "buck2 toolchains flake";
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

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
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

        buck2BuildInputs =
          [
            pkgs.bash
            pkgs.coreutils
            pkgs.cacert
            pkgs.gnused
            pkgs.git
            pkgs.nix
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.stdenv.cc.bintools
            pkgs.darwin.cctools
          ];

        hsPkgs = pkgs.haskell.packages.ghc965;

        toolchainLibraries = import ./ghc-toolchain-libraries.nix;

        haskellPackages =
          let
            packages = builtins.map (n: hsPkgs."${n}") toolchainLibraries;
            isHaskellLibrary = p: p ? isHaskellLibrary;
          in
          builtins.listToAttrs (
            builtins.map (p: {
              "name" = p.pname;
              "value" = p.drvPath;
            }) (builtins.filter isHaskellLibrary (pkgs.lib.closePropagation packages))
          );
      in
      {
        packages = {
          ghc = pkgs.haskell.packages.ghc965.ghc;
          hsc2hs = pkgs.haskell.packages.ghc965.hsc2hs;
          inherit haskellPackages;

          bash = pkgs.writeShellScriptBin "bash" ''
            export PATH='${pkgs.lib.makeSearchPath "bin" buck2BuildInputs}'
            exec "$BASH" "$@"
          '';

          cxx = pkgs.stdenv.mkDerivation {
            name = "buck2-cxx";
            dontUnpack = true;
            dontCheck = true;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            buildPhase = ''
              function capture_env() {
                  # variables to export, all variables with names beginning with one of these are exported
                  local -ar vars=(
                      NIX_CC_WRAPPER_TARGET_HOST_
                      NIX_CFLAGS_COMPILE
                      NIX_DONT_SET_RPATH
                      NIX_ENFORCE_NO_NATIVE
                      NIX_HARDENING_ENABLE
                      NIX_IGNORE_LD_THROUGH_GCC
                      NIX_LDFLAGS
                      NIX_NO_SELF_RPATH
                  )
                  for prefix in "''${vars[@]}"; do
                      for v in $( eval 'echo "''${!'"$prefix"'@}"' ); do
                          echo "--set"
                          echo "$v"
                          echo "''${!v}"
                      done
                  done
              }

              mkdir -p "$out/bin"

              for tool in ar nm objcopy ranlib strip; do
                  ln -st "$out/bin" "$NIX_CC/bin/$tool"
              done

              mapfile -t < <(capture_env)

              makeWrapper "$NIX_CC/bin/$CC" "$out/bin/cc" "''${MAPFILE[@]}"
              makeWrapper "$NIX_CC/bin/$CXX" "$out/bin/c++" "''${MAPFILE[@]}"
            '';
          };
          python = pkgs.python3.withPackages (ps: with ps; [ grpcio ]);
        };
      }
    );
}
