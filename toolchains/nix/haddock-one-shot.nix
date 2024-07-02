{ mkDerivation, base, fetchzip, fetchpatch, filepath, lib }:
mkDerivation {
  pname = "haddock";
  version = "2.30.0";
  src = fetchzip {
    url = "https://gitlab.haskell.org/ghc/haddock/-/archive/bb7b9480b0825d3fa978e61c7faf25dce718a305/haddock-bb7b9480b0825d3fa978e61c7faf25dce718a305.tar.gz";
    sha256 = "1jlcwb70d4020z3scwb0di4k5k0jirj1sy2d367pl49gyqxsqmih";
  };
  patches = [
    # Add support for incremental/one-shot haddock
    # https://gitlab.haskell.org/trac-sjoerd_visscher/haddock/-/commit/f040b69424e1024155cc8999ee050165e8f8ae24
    (fetchpatch {
      url = "https://gitlab.haskell.org/trac-sjoerd_visscher/haddock/-/commit/f040b69424e1024155cc8999ee050165e8f8ae24.patch";
      sha256 = "sha256-6zVKcFXUEUdQrxh4yDnKzH2R2XBTHvQ3Gvj4fngGQ4o=";
    })
    # Merge package interfaces when generating contents
    # https://gitlab.haskell.org/trac-sjoerd_visscher/haddock/-/commit/4dc1bfc946f87ee2ce802d9fdd3dc3b2e1734a52
    (fetchpatch {
      url = "https://gitlab.haskell.org/trac-sjoerd_visscher/haddock/-/commit/4dc1bfc946f87ee2ce802d9fdd3dc3b2e1734a52.patch";
      sha256 = "sha256-CIY27rDpqwTwTqn0xMCU3754iuCUaaQ1l8yejSqSFLE=";
    })
    # Don't load in attachInstances in one shot mode
    # https://gitlab.haskell.org/trac-sjoerd_visscher/haddock/-/commit/b11c4d939bfd53e26de4d298266e6a5c46f73009
    (fetchpatch {
      url = "https://gitlab.haskell.org/trac-sjoerd_visscher/haddock/-/commit/b11c4d939bfd53e26de4d298266e6a5c46f73009.patch";
      sha256 = "sha256-/O/DtHUI+smFkWMXhxJP1KGwyQGKJuIpPfTVwnJUtgI=";
    })
    # Update DynFlags with extensions set in source
    # https://gitlab.haskell.org/ghc/haddock/-/commit/d6854b68e5da314d611528fc0a970d4f22c7afd4
    (fetchpatch {
      url = "https://gitlab.haskell.org/ghc/haddock/-/commit/d6854b68e5da314d611528fc0a970d4f22c7afd4.patch";
      sha256 = "sha256-Vyy7ADzzErHj5UebbpF/Eps+OOaLXJGZEDDLsP4Qd9U=";
    })
  ];
  isLibrary = false;
  configureFlags = [ "-fin-ghc-tree" ];
  isExecutable = true;
  executableHaskellDepends = [ base ];
  testHaskellDepends = [ base filepath ];
  doHaddock = false;
  doCheck = false;
  preCheck = "unset GHC_PACKAGE_PATH";
  homepage = "http://www.haskell.org/haddock/";
  description = "A documentation-generation tool for Haskell libraries";
  license = lib.licenses.bsd3;
  mainProgram = "haddock";
}
