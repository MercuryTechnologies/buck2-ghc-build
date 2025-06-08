# HOW TO USE THIS MODULE:
#
#    load("//toolchains/nix.bzl", "nix")

## ---------------------------------------------------------------------------------------------------------------------
load("@prelude//haskell:toolchain.bzl", "NativeToolchainLibrary")

def __flake_impl(ctx: AnalysisContext, flake: Artifact, package: str, binary: str | None, binaries: list[str], lib_name: str | None) -> list[Provider]:
    # calls nix build path:<flake-path>#<package>

    deps = [o[DefaultInfo].default_outputs[0] for o in ctx.attrs.deps]

    if ctx.attrs.suffix:
        out_link = ctx.actions.declare_output("out.link-{}".format(ctx.attrs.suffix))
    else:
        out_link = ctx.actions.declare_output("out.link")

    nix_build = cmd_args([
        "env",
        "--",  # this is needed to avoid "Spawning executable `nix` failed: Failed to spawn a process"
        "nix",
        "build",
        cmd_args("--out-link", cmd_args(out_link.as_output(), parent = 1, absolute_suffix = "/out.link"), hidden = [out_link.as_output()]),
        cmd_args(cmd_args(flake, package, delimiter = "#"), absolute_prefix = "path:"),
    ])
    ctx.actions.run(nix_build, category = "nix_flake", local_only = True)

    run_info = []
    if binary:
        run_info.append(
            RunInfo(
                args = cmd_args(out_link, "bin", ctx.attrs.binary, delimiter = "/"),
            ),
        )

    native_lib = []
    if lib_name:
        native_lib.append(
            NativeToolchainLibrary(
                name = lib_name,
                lib_path = cmd_args(out_link, "lib", delimiter = "/", absolute_prefix = "-L"),
            ),
        )

    nix_dynamic_info = NixDynamicInfo(
        dynamic = _read_out_link(ctx, out_link),
    )

    sub_targets = {
        bin: [DefaultInfo(default_output = out_link), RunInfo(args = cmd_args(out_link, "bin", bin, delimiter = "/"))]
        for bin in binaries
    }

    return [
        DefaultInfo(
            default_output = out_link,
            sub_targets = sub_targets,
        ),
        # Note: This is just a path to the `bin` directory, it doesn't actually
        # have to exist!
        BinDirInfo(
            args = cmd_args(out_link, "bin", delimiter = "/"),
        ),
        # absolute nix path information will be recorded here. It is a dynamic value.
        nix_dynamic_info,
    ] + run_info + native_lib

__flake = rule(
    impl = lambda ctx: __flake_impl(ctx, ctx.attrs.flake, ctx.attrs.package or ctx.label.name, ctx.attrs.binary, ctx.attrs.binaries, ctx.attrs.lib_name),
    attrs = {
        "binary": attrs.option(attrs.string(), default = None),
        "binaries": attrs.list(attrs.string(), default = []),
        "deps": attrs.list(attrs.dep(), default = []),
        "flake": attrs.source(allow_directory = True),
        "package": attrs.option(attrs.string(), doc = "name of the flake output, defaults to label name", default = None),
        "suffix": attrs.option(attrs.string(), default = None),
        "lib_name": attrs.option(attrs.string(), default = None),
    },
)

def _read_out_link_dynamic_impl(actions, read_link):
    nix_path = read_link.read_string()
    return [NixPathInfo(path = nix_path)]

_read_out_link_dynamic = dynamic_actions(
    impl = _read_out_link_dynamic_impl,
    attrs = {
        "read_link": dynattrs.artifact_value(),
    },
)

def _read_out_link(ctx: AnalysisContext, out_link: Artifact) -> DynamicValue:
    read_link = ctx.actions.declare_output("read_link")
    ctx.actions.run(
        cmd_args("bash", "-ec", """readlink $1 > $2""", "--", out_link, read_link.as_output()),
        category = "nix_path",
        local_only = True,
    )

    dyn_nix_path = ctx.actions.dynamic_output_new(_read_out_link_dynamic(
        read_link = read_link,
    ))

    return dyn_nix_path

BinDirInfo = provider(
    doc = """Provides the path of the `/bin` directory of a derivation output.""",
    fields = {
        "args": provider_field(cmd_args),
    },
)

NixDynamicInfo = provider(
    doc = """Provides nix-side dynamic information.""",
    fields = {
        "dynamic": DynamicValue,
    },
)

NixPathInfo = provider(
    doc = """Provides the absolute /nix/store path.""",
    fields = {
        "path": str,
    },
)

## ---------------------------------------------------------------------------------------------------------------------

nix = struct(
    rules = struct(
        flake = __flake,
    ),
    macros = struct(),
)
