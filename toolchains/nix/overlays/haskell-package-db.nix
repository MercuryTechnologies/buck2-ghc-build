self: super:

let
  makePackageDB = p: p.overrideAttrs (final: prev: {
    postInstall = (prev.postInstall or "") + ''
      ghc-pkg recache --package-db $packageConfDir
    '';
  });
in
{
  haskell = super.haskell // {
    packages = self.lib.attrsets.mapAttrs (name: value: if value ? isHaskellLibrary then makePackageDB value else value) super.haskell.packages;
  };
}
