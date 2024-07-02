{
  stdenvNoCC,
  sigtool,
  cctools,
}: let
  stdenv = stdenvNoCC;
in
  stdenv.mkDerivation {
    name = "signing-utils-with-get-task-allow";

    buildCommand = "substituteAll ${./utils.sh} $out";

    # Substituted variables
    inherit sigtool;
    codesignAllocate = "${cctools}/bin/${cctools.targetPrefix}codesign_allocate";
  }
