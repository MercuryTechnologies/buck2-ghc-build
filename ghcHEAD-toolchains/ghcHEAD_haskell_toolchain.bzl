load(
    "@prelude//haskell:toolchain.bzl",
    "HaskellPlatformInfo",
    "HaskellToolchainInfo",
    "HaskellPackage",
    "HaskellPackagesInfo",
    "HaskellPackageDbTSet",
    "DynamicHaskellPackageDbInfo",
)
load("@prelude//utils:graph_utils.bzl", "post_order_traversal")
load(":libs.bzl", "toolchain_libraries")


def _build_pkg_db(ctx: AnalysisContext, ghc_pkg, ghc_version, packages: list[Artifact], output: Artifact, identifier: str = ""):
    init_db = cmd_args(ghc_pkg, "init", output.as_output(), delimiter = " ")
    copy_cfgs = cmd_args(
        'package_conf_dir="lib/ghc-{}/lib/package.conf.d"; '.format(ghc_version),
        "for lib in ", cmd_args(packages, delimiter = " "), "; do",
        "cp -t", output.as_output(), '"$lib/$package_conf_dir/"*.conf; ',
        "done",
        delimiter = " ",
    )
    recache = cmd_args(
        ghc_pkg,
        "recache",
        "--package-db", output.as_output(),
        delimiter = " ",
    )

    ctx.actions.run(
        cmd_args([
            "bash",
            "-ec",
            cmd_args(init_db, copy_cfgs, recache, delimiter="\n"),
        ]),
        category = "ghc_db",
        identifier = identifier,
    )


def _build_package_db(ctx: AnalysisContext, ghc: Artifact, ghc_pkg: Artifact, haddock: Artifact) -> (Artifact, DynamicValue):
    pkg_db = ctx.actions.declare_output("db", dir = True)

    ghc_info = ctx.actions.declare_output("ghc_info.json")
    ctx.actions.run(
        cmd_args("bash", "-ec", '''printf '{ "version": "%s" }\n' "$( $1 --numeric-version )" > "$2" ''', "--", ghc, ghc_info.as_output()),
        category = "ghc_info",
        local_only = True,
    )

    package_dbs = {
        pkg : ctx.actions.declare_output(pkg, "db")
        for pkg in toolchain_libraries
    }

    def get_outputs(info: list[str] | dict[str, typing.Any]):
        """Get outputs for `inputDrvs`, regardless of the nix version that produced the information.

        In older nix versions, the information was just a list of strings, in newer versions it is
        a dict having a `outputs` field (and a `dynamicOutputs` field).
        """
        if isinstance(info, list):
            return info
        else:
            return info["outputs"]

    def create_pkg_dbs(ctx, artifacts, _resolved, outputs, package_dbs=package_dbs, ghc_info=ghc_info):
        json_ghc = artifacts[ghc_info].read_json()

        ghc_version = json_ghc["version"]

        pkgs = {}

        builtin_libs = [ output for name, output in package_dbs.items() ]

        builtin_db = ctx.actions.declare_output("builtin_db", dir=True)
        ctx.actions.run(
            cmd_args("mkdir", "-p", builtin_db.as_output()),
            category="builtin_db",
        )
        for lib in builtin_libs:
            ctx.actions.symlink_file(outputs[lib].as_output(), builtin_db)

        _build_pkg_db(
            ctx,
            ghc_pkg,
            ghc_version,
            [],
            output = outputs[pkg_db],
        )

        return [DynamicHaskellPackageDbInfo(packages = pkgs)]

    dyn_pkgs_info = ctx.actions.dynamic_output(
        dynamic = [ghc_info],
        promises = [],
        inputs = [],
        outputs = [pkg_db.as_output()] + [db.as_output() for db in package_dbs.values()],
        f = create_pkg_dbs,
    )

    return pkg_db, dyn_pkgs_info

def _ghcHEAD_haskell_toolchain_impl(ctx: AnalysisContext) -> list[Provider]:
    #ghc = ctx.attrs.ghc[RunInfo]
    #ghc_pkg = ctx.attrs.ghc_pkg[RunInfo]

    ghc = ctx.actions.declare_output("ghc")
    ghc_pkg = ctx.actions.declare_output("ghc-pkg")
    haddock = ctx.actions.declare_output("haddock")

    cmd = cmd_args(
        ctx.attrs.script,
        ghc.as_output(),
        ghc_pkg.as_output(),
        haddock.as_output(),
    )
    ctx.actions.run(
        cmd,
        category = "nix_env_haskell",
        local_only = True,
    )

    pkg_db, dynamic = _build_package_db(ctx, ghc, ghc_pkg, haddock)

    return [
        DefaultInfo(),
        HaskellToolchainInfo(
            compiler = ghc,
            packager = ghc_pkg,
            linker = ghc,
            haddock = haddock,
            compiler_flags = ctx.attrs.compiler_flags,
            linker_flags = ctx.attrs.linker_flags,
            ghci_script_template = ctx.attrs._ghci_script_template,
            ghci_iserv_template = ctx.attrs._ghci_iserv_template,
            script_template_processor = ctx.attrs._script_template_processor,
            packages = HaskellPackagesInfo(package_db = pkg_db, dynamic = dynamic),
        ),
        HaskellPlatformInfo(
            name = host_info().arch,
        ),
    ]

ghcHEAD_haskell_toolchain = rule(
    impl = _ghcHEAD_haskell_toolchain_impl,
    attrs = {
        "script": attrs.source(),
        "_ghci_script_template": attrs.source(default = "//:ghci_script_template"),
        "_ghci_iserv_template": attrs.source(default = "//:ghci_iserv_template"),
        "_script_template_processor": attrs.dep(
            providers = [RunInfo],
            default = "prelude//haskell/tools:script_template_processor",
        ),
        "compiler_flags": attrs.list(
            attrs.string(),
            default = [],
        ),
        "linker_flags": attrs.list(
            attrs.string(),
            default = [],
        ),
    },
    is_toolchain_rule = True,
)
