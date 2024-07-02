{ haskell, toolchainLibraries }:

haskell.packages.ghc98.ghcWithPackages (p: builtins.map (name: p."${name}") toolchainLibraries)
