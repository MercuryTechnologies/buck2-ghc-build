# Nix expression to build Buck2 from source.
# Based, in part, on https://github.com/thoughtpolice/buck2-nix/blob/c602d0f44f03310a89f209a322bb122b0d3c557a/buck/nix/buck2/default.nix
#
# To update Buck2:
# - change the `git_rev` and `src.hash` attributes below.
# - copy a fresh `Cargo.lock` from Buck2.
{
  lib,
  darwin,
  fetchFromGitHub,
  installShellFiles,
  fenix,
  makeRustPlatform,
  openssl,
  pkg-config,
  protobuf,
  sqlite,
  stdenv,
  fetchpatch,
}:
let
  rustChannel = fenix.latest;
  rustPlatform = makeRustPlatform {
    inherit (rustChannel) cargo;
    rustc = rustChannel.rustc // {
      # newer nixpkgs' `buildRustPackage` expect rustc to provide `targetPlatforms` and `badTargetPlatforms`
      # see https://github.com/oxalica/rust-overlay/issues/194
      # TODO remove this workaround once fenix is recent enough
      targetPlatforms = lib.platforms.all;
      badTargetPlatforms = [ ];
    };
  };
in
rustPlatform.buildRustPackage rec {
  pname = "buck2";
  git_rev = "2025-02-15";
  version = "git-${git_rev}";

  src = fetchFromGitHub {
    owner = "facebook";
    repo = pname;
    rev = git_rev;
    hash = "sha256-F911L1Auu7DVRV+AUHowkf5jDPHaXAspi3vnL31RPEc=";
  };

  patches = [
    # Only upload large files once.
    #
    # See: https://github.com/facebook/buck2/pull/750
    ./pr750.patch

    # remote_execution: upload action results to ActionCache.
    #
    # See: https://github.com/facebook/buck2/pull/771
    ./pr771.patch

    # Use preferred digest hashing algorithm for action permission checker.
    #
    # See: https://github.com/facebook/buck2/pull/784
    ./pr784.patch

    # Allow //A/B/C as a valid name for //A/B/C:C in BUCK files
    ./pr925.patch

    # solve rebuild / cache invalidation issue
    (fetchpatch {
      url = "https://github.com/MercuryTechnologies/buck2/commit/aa3569e50ae58419a35583e16e6b5720c63054b6.diff";
      hash = "sha256-0iwIyuggmf0tFXgS2c53aMnlp7dawfjeN2iqxsMjaDE=";
    })

    # Raise ulimit for file descriptors to prevent "Too many open files (os error 24)".
    #
    # See: https://github.com/facebook/buck2/pull/928
    (fetchpatch {
      url = "https://github.com/facebook/buck2/commit/0c83b63d9931eb951ff13647bf966058cced0509.diff";
      hash = "sha256-pTya7NNp7g/l2+36TuxQWA7TncfYnKLIH1zi4UbuB6Q=";
    })

    # Made persistent-worker-generated Artifacts uploaded to remote cache.
    # Previously, artifacts from local worker were not regarded as local, which is a bug.
    # CommandExecutionKind::LocalWorker => was_locally_executed = true
    (fetchpatch {
      url = "https://github.com/MercuryTechnologies/buck2/commit/4be7a85061cd8933d8ea8e8811a9ea583848499c.diff";
      hash = "sha256-4hpK29S1PG0uri55hD+ta3170RltmeQQ9ZjFVWaAMtw=";
    })
  ];

  cargoLock = {
    lockFile = ./Cargo.lock;
    allowBuiltinFetchGit = true;
  };

  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
    chmod +w Cargo.lock  # Huh???
  '';

  nativeBuildInputs = [
    installShellFiles
    protobuf
    pkg-config
  ];
  buildInputs =
    [
      openssl
      sqlite
    ]
    ++ lib.optionals stdenv.isDarwin [
      darwin.apple_sdk.frameworks.CoreFoundation
      darwin.apple_sdk.frameworks.CoreServices
      darwin.apple_sdk.frameworks.IOKit
      darwin.apple_sdk.frameworks.Security
    ];

  BUCK2_BUILD_PROTOC = "${protobuf}/bin/protoc";
  BUCK2_BUILD_PROTOC_INCLUDE = "${protobuf}/include";

  doCheck = false;
  dontStrip = true; # XXX (aseipp): cargo will delete dwarf info but leave symbols for backtraces

  postInstall = ''
    mv $out/bin/buck2     $out/bin/buck
    ln -sfv $out/bin/buck $out/bin/buck2
    mv $out/bin/starlark  $out/bin/buck2-starlark
    mv $out/bin/read_dump $out/bin/buck2-read_dump

    installShellCompletion --cmd buck2 \
      --bash <( $out/bin/buck2 completion bash ) \
      --fish <( $out/bin/buck2 completion fish ) \
      --zsh <( $out/bin/buck2 completion zsh )
  '';

  meta = with lib; {
    description = "Build system, successor to Buck";
    homepage = "https://buck2.build/";
    changelog = "https://github.com/facebook/buck2/blob/main/CHANGELOG.md";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "buck2";
  };
}
