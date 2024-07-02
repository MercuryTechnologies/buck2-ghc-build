{
  description = "buck2 toolchains flake";

  inputs = {
    nixpkgs.url = "github:MercuryTechnologies/nixpkgs/ghc962";
    flake-compat.url = "github:nix-community/flake-compat";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = import ./overlays;
          config = {
            allowUnfree = true;
            allowBroken = true;
          };
        };
        lib = pkgs.lib;
        compilerName = import ./compiler.nix;
        hsPkgs = pkgs.haskell.packages.${compilerName};
        buck2BuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.cacert
          pkgs.gnused
          pkgs.git
          pkgs.nix
        ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          pkgs.stdenv.cc.bintools
          pkgs.darwin.cctools
        ];

        toolchainLibraries = import ./ghc-toolchain-libraries.nix;

        ghcWithPackages = import ./ghc-with-packages.nix { inherit (pkgs) haskell; inherit toolchainLibraries; };

        haddock-one-shot = hsPkgs.callPackage ./haddock-one-shot.nix { };
        haddock = pkgs.writeShellScriptBin "haddock" ''
          libdir="$( ${ghcWithPackages}/bin/ghc --print-libdir )"
          exec ${haddock-one-shot}/bin/haddock -B "$libdir" -l "$libdir" "''${@}"
        '';

        haskellPackages =
          builtins.listToAttrs (builtins.map (p: { "name" = p.pname; "value" = p; }) haskellLibraries);

        haskellLibraries =
          let
            packages = builtins.map (n: hsPkgs."${n}") toolchainLibraries;
            isHaskellLibrary = p: p ? isHaskellLibrary;
          in
          builtins.filter isHaskellLibrary (lib.closePropagation packages);
      in
      {
        apps.dockerBuild =
          { program = "${self.packages.${system}.dockerImage}"; type = "app"; };

        packages = {
          dockerImage =
            let
              inherit (pkgs) dockerTools;
              inherit (self.packages.${system}) bash ghc cxx python;
            in
            dockerTools.streamNixShellImage {
              name = "nix-build";
              drv = pkgs.mkShell.override { stdenv = pkgs.stdenvNoCC; }
                {
                  PATH = pkgs.lib.makeBinPath [ pkgs.bash pkgs.coreutils ];
                  nativeBuildInputs = [ bash cxx ghc haddock python ] ++ haskellLibraries;
                };
              tag = "latest";
            };

          inherit ghcWithPackages haddock haskellPackages;
          inherit (hsPkgs) ghc;

          bash = pkgs.writeShellScriptBin "bash" ''
            export PATH='${ pkgs.lib.makeSearchPath "bin" buck2BuildInputs }'
            exec "$BASH" "$@"
          '';

          cxx = pkgs.stdenv.mkDerivation
            {
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
          python = pkgs.python3;
        };
      });
}
