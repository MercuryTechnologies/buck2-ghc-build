# Nix expression to build Buck2 from source.
# Based, in part, on https://github.com/thoughtpolice/buck2-nix/blob/c602d0f44f03310a89f209a322bb122b0d3c557a/buck/nix/buck2/default.nix
#
# To update Buck2:
# - change the `git_rev` and `src.hash` attributes below.
# - copy a fresh `Cargo.lock` from Buck2.

{ lib
, darwin
, fetchFromGitHub
, installShellFiles
, makeRustPlatform
, openssl
, pkg-config
, protobuf
, rust-bin
, sqlite
, stdenv
}:

let
  # based on Buck2's `rust-toolchain` file.
  rust-nightly = rust-bin.nightly."2024-06-08".default.override {
    extensions = [ "llvm-tools-preview" "rustc-dev" "rust-src" ];
  };
  rustPlatform = makeRustPlatform {
    cargo = rust-nightly;
    rustc = rust-nightly;
  };
in

rustPlatform.buildRustPackage rec {
  pname = "buck2";
  git_rev = "391bcf0f0faa50996a441c9329f219a25170957c";
  version = "git-${git_rev}";

  src = fetchFromGitHub {
    owner = "facebook";
    repo = pname;
    rev = git_rev;
    hash = "sha256-mY1s4vm/2TirjnvyNV8bfJ248qibJL2ZTF36awnVP7Q=";
  };

  patches = [
    ./oss-rbe-caching_pr477.diff
  ];

  cargoLock = {
    lockFile = ./Cargo.lock;
    allowBuiltinFetchGit = true;
  };

  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [ installShellFiles protobuf pkg-config ];
  buildInputs = [ openssl sqlite ] ++ lib.optionals stdenv.isDarwin [
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
      --zsh <( $out/bin/buck2 completion zsh )
  '';

  meta = with lib; {
    description = "Build system, successor to Buck";
    homepage = "https://buck2.build/";
    changelog = "https://github.com/facebook/buck2/blob/main/CHANGELOG.md";
    license = licenses.asl20;
    maintainers = [];
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "buck2";
  };
}
