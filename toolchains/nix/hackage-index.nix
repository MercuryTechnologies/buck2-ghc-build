# You may need to update this to the latest if you're unable to update a
# Hackage dependency.
#
# Update steps:
# 1. Go to the Github repo: https://github.com/commercialhaskell/all-cabal-hashes/tree/hackage
# 2. Copy the latest commit and replace the existing one in `url` below (its
#    the stuff after `/archive/` and before `.tar.gz`)
# 3. Try to do a `nix-build`. It will error about the sha256 not matching.  I get this output:
#    ```
#    hash mismatch in fixed-output derivation '/nix/store/h1ka4vi6zg8gn8zayffc98wpm9yri0i0-c038437c4925ef1cda0c2eea87cadf472a49deb7.tar.gz':
#      wanted: sha256:0cfd5g4d1nbfnc9pcwrd5j6n8hfnxvws103z4f18qml77sfpg9h1
#      got:    sha256:1xh7b4h235gw9x540sl1c5j80fzdpyavgnfg69lkxr2ixkq4aipp
#    cannot build derivation '/nix/store/j0xsc8gq5xsaa1dqs0z6shp2a4dcds8i-all-cabal-hashes-component-extra-1.7.9.drv': 1 dependencies couldn't be built
#    cannot build derivation '/nix/store/a0h29y1dhbxda46p5girvvl7mddgywxy-cabal2nix-extra-1.7.9.drv': 1 dependencies couldn't be built
#    error: build of '/nix/store/a0h29y1dhbxda46p5girvvl7mddgywxy-cabal2nix-extra-1.7.9.drv' failed
#    (use '--show-trace' to show detailed location information)
#    ```
# 4. Copy the correct sha256 in. In the above splice, that's the `got: sha256:$(copy meeeee)` stuff.
# 5. Try to do the `nix-shell` again.
{
  url = "https://api.github.com/repos/commercialhaskell/all-cabal-hashes/tarball/d665188efca2c4b241c0a059fcafcd2a4aace8a9";
  sha256 = "sha256-T34DfEu43mFDLXn1PImFp1jWo0rfpWnJB7e7INRk22A=";
}
