self: super: let
  # For GHC to generate a core dump file when crashing with a segmentation fault,
  # the GHC binary should be code-signed with the get-task-allow entitlement on macos.
  # As code-signing is carried out by a setup hook for GHC on nixpkgs, we customize the
  # hook with custom entitlements.
  # ref. https://nasa.github.io/trick/howto_guides/How-to-dump-core-file-on-MacOS.html
  signingUtilsWithGetTaskAllow =
    self.callPackage ./ghc/signing-utils-with-get-task-allow/default.nix {inherit (self.darwin) cctools sigtool;};

  autoSignDarwinBinariesWithGetTaskAllowHook = self.darwin.autoSignDarwinBinariesHook.overrideAttrs (_: {
    propagatedBuildInputs = [signingUtilsWithGetTaskAllow];
  });

  mkGhc = {
    version,
    compiler,
    src,
    patches,
  }:
    ((compiler.overrideAttrs {
        ghcVersion = version;
        version = version;
      })
      .override {
        # The GHC builder in nixpkgs first builds hadrian with the
        # source tree provided here and then uses the built hadrian to
        # build the rest of GHC. We need to make sure our patches get
        # included in this `src`, then, rather than modifying the tree in
        # the `patchPhase` or `postPatch` of the outer builder.
        ghcSrc =
          (self.applyPatches {
            inherit src patches;
          })
          .overrideAttrs (drv: {
            # After patching the GHC, we need to regenerate compiler/GHC/Cmm/Parser.hs
            # for which a pre-generated version was included in the GHC source
            # distribution. So here the generated file is deleted and the original
            # source is restored for a patch to be applied.
            prePatch = ''
              echo "Recreating GHC.Cmm.Parser.y"
              mv compiler/GHC/Cmm/Parser.y.source compiler/GHC/Cmm/Parser.y
              rm compiler/GHC/Cmm/Parser.hs
            '';
            postPatch = ''
              ed -s compiler/GHC/Driver/MakeFile/JSON.hs <<EOF
              0 i
              {-# LANGUAGE DeriveGeneric #-}
              {-# LANGUAGE GeneralizedNewtypeDeriving #-}
              {-# LANGUAGE ImportQualifiedPost #-}
              {-# LANGUAGE NamedFieldPuns #-}
              .
              w
              EOF
              ed -s compiler/GHC/Driver/MakeFile.hs <<EOF
              0 i
              {-# LANGUAGE NamedFieldPuns #-}
              .
              w
              EOF
            '';
            nativeBuildInputs = [self.ed] ++ drv.nativeBuildInputs or [];
          });
        # Add the `get-task-allow` entitlement on macOS to generate core dumps on
        # segfault.
        autoSignDarwinBinariesHook = autoSignDarwinBinariesWithGetTaskAllowHook;
      })
    .overrideAttrs (drv: {
      # Regenerate `configure` from `configure.ac`.
      postPatch = ''
        ${self.autoconf}/bin/autoreconf --force --install --include=m4
      '';

      passthru =
        drv.passthru
        // {
          haskellCompilerName = "ghc-${version}";
        };
    });

  ghc982Src = let
    version = "9.8.2";
  in
    self.fetchurl {
      url = "https://downloads.haskell.org/ghc/${version}/ghc-${version}-src.tar.xz";
      hash = "sha256-4vt6fddGEjfSLoNlqD7dnhp30uFdBF85RTloRah3gck=";
    };

  patches = [
    # - Alexis' patch: byte-code linking inefficiency mitigated by this
    # - fixed a segfault problem in Alexis' patch.
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/9e651c2ae0e844518b1a7e86511d906fb43a9aa5.diff";
      hash = "sha256-hZt1bBTX0oUM/DhrO+QWc5vJNnc+eLd+6qVg40zilIg=";
    })

    # byte code and iface breakpoints changes and bug fix (backported to GHC 9.8.2)
    # [1] https://gitlab.haskell.org/ghc/ghc/-/merge_requests/10448
    # [2] https://gitlab.haskell.org/ghc/ghc/-/merge_requests/11026
    # (the other two patches were merged onto 9.8)
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/354b36673f934a0c821eccbf991fb7ca0facc924.diff";
      hash = "sha256-IdIABJf1v5XnRv6PjHf2nATuABKUo+xPXlzNDbiRRAY=";
    })
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/56061b9da73cf42fe292fe61725439a2fa8a8967.diff";
      hash = "sha256-Kxiq0fHH142jbbrr57DkTq3Af/IS8Z54JW7Jm1DRU8A=";
    })

    # memory-efficient GHC
    # [1] https://gitlab.haskell.org/ghc/ghc/-/merge_requests/12070 -> Weird issue with cabal mixins (parsec-xbrl-sec) -> so disabled.
    # [2] https://gitlab.haskell.org/ghc/ghc/-/merge_requests/12127
    # [3] https://gitlab.haskell.org/ghc/ghc/-/merge_requests/12138
    #(self.fetchpatch {
    #  url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/55b1254bbeeaa05c72de7dfeaa7d01f71448c5cc.diff";
    #  hash = "sha256-+MBwSrP9Zho7CVVkT7U6+qMG1wpB56SWnw0JlF74HsM=";
    #})
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/b49a6fb60eedcafda16a6368d561b00f2730fe75.diff";
      hash = "sha256-rUEN8oZGagxNiEV+LjCkeEE33UhJViyHKmzbHW0Wy9s=";
    })
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/5a33e66c60bd8de8115b929a91a270d61e6612a6.diff";
      hash = "sha256-V2z64npQkBZisFRf0z26KOx7sCxaoQ8D5fzArZYi5hk=";
    })

    # Fix "internal error: scavenge_one: strange object 23" crash
    # https://gitlab.haskell.org/ghc/ghc/-/issues/23375
    # https://gitlab.haskell.org/ghc/ghc/-/merge_requests/10523
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/68f168c03ab4aedfaefe9a516aa0fb6a1f4f8d5c.diff";
      hash = "sha256-ocdfB2tMej6eCB5BbEPVgH49H0Eg18wRbo02sfzoffU=";
    })

    # Fix sticky recompilation when changing byte_code_linking-related flags
    # https://gitlab.haskell.org/ghc/ghc/-/issues/24175 -> not in 9.8
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/044fb68c88bdaa44366099f9059732f2df2db2d4.diff";
      hash = "sha256-O7fBk94iAFXtvtrzdRhxvA8pJqwZXV4PG1OdMv8KRo8=";
    })

    # Make -ddump-json and -ddump-to-file cowork
    # https://gitlab.haskell.org/ghc/ghc/-/issues/22959
    # https://gitlab.haskell.org/ghc/ghc/-/merge_requests/9994 -> not in 9.8
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/5737fe7a24619b50560feeb773658616101f70f9.diff";
      hash = "sha256-orW85xRcfPsa+TzH1uD7jyI0YhfclOOsC+veMGPB/Vo=";
    })

    # add -dep-json flag for emitting machine-readable dependency info
    # https://gitlab.haskell.org/ghc/ghc/-/merge_requests/11994
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/66cd9e04194e34a9bea8c718c994a853686ebfc9.diff";
      hash = "sha256-Z+NSblpX0J9SowW1kampcIElzo0pVzNHvLl0t6V6iRk=";
    })

    # refactor quadratic search in warnMissingHomeModules
    # https://gitlab.haskell.org/ghc/ghc/-/merge_requests/12607
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/c68ca44ad912576df7ab05103cef4d26cf6cea54.diff";
      hash = "sha256-am8Ns5l4RrPdNMnnQ8P1HNc7/1pWfYvdebYYkDHDnaU=";
    })
    #./ghc-fix-quadratic-search-warn-missing-home-modules.diff

    # bytecode linking
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/054e81f502466c0418e51929fe92c7b899c1de9b.diff";
      hash = "sha256-7MhLvPhUArOqwCmNigjb5gSuDHzEuLuRhzr0tSTJ6V0=";
    })
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/6851a2ab04ee18b70b82fdd71863e25a5c21a8e7.diff";
      hash = "sha256-j40Qfy18A3zIlwamsNhdCnufS/fMHJ1Xd/QXtSYQqm4=";
    })
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/be81a0f26da3fcea3e235093552911088b24ce54.diff";
      hash = "sha256-mNAlQzGwMCwAgR+wCyjvtbM/ULO3IdN1t+aFfQkGVQ0=";
    })
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/c76daf79e519f351b57b2937444973a729a79ef2.diff";
      hash = "sha256-GQnvGKvC3Tuqm7nNET0/vZP7wGFRT7AlIkZtxORDIHA=";
    })
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/f0de47eb22983dbdbacde611182bd408f63c7b32.diff";
      hash = "sha256-WxZJbnanM5I6udII7bHqrbKSTogdSqW0hX2YuO5NQHI=";
    })
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/6e218283b1d677013a5b960fd6f5ff1830056da3.diff";
      hash = "sha256-NJJFovPCaavH1oYJE6q5XbNJdXHyLNiHHR8lZSzBTok=";
    })

    (self.fetchpatch {
      url = "https://gitlab.haskell.org/torsten.schmits/ghc/-/commit/8a58e4aefe2684f4f913bd3423a0b3c4d36fa5af.diff";
      hash = "sha256-QQvY9n0q+JkOv40MHj3BxNz6vvjxTnKaKGPwBA0HYZo=";
    })

    # --show-iface-abi-hash
    # https://gitlab.haskell.org/ghc/ghc/-/tree/wip/show-iface-abi-hash?ref_type=heads
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/a833390f7ace8531a6b261b1f87f74d8a510a19f.diff";
      hash = "sha256-YqI0E63zUb+q63h99PrsmC5sufafo+fNQKFpmMf6x1c=";
    })

    # finder: Add `IsBootInterface` to finder cache keys
    # https://gitlab.haskell.org/ghc/ghc/-/merge_requests/13237
    (self.fetchpatch {
      url = "https://gitlab.haskell.org/wavewave/ghc/-/commit/27463f979831531b816f25e118b20a2d02505bf3.diff";
      hash = "sha256-rUH3FipJLk+sSbaC3B9wf93gjKlhacDX59Hwb8G4a1U=";
    })
  ];
in {
  haskell =
    super.haskell
    // {
      compiler =
        super.haskell.compiler
        // {
          # NOTE: unfortunately, there is no ghc982 attribute. so we reuse ghc981 attribute.
          # TODO: when nixpkgs is updated again, change this.
          ghc981 = mkGhc {
            version = "9.8.2";
            compiler = super.haskell.compiler.ghc981;
            src = ghc982Src;
            inherit patches;
          };
        };
    };
}
