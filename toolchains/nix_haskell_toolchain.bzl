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

def __nix_build_drv(actions, drv: str, package: str, deps) -> Artifact:
    # calls nix build /path/to/file.drv^*

    out_link = actions.declare_output(package, "out.link")
    nix_build = cmd_args([
        "bash",
        "-ec",
        '''
        nix build --out-link "$1" "$2"
        ''',
        "--",
        out_link.as_output(),
        cmd_args(drv, format = "{}^*"),
    ], hidden = deps)
    actions.run(nix_build, category = "nix_build", identifier = package, local_only = True)

    return out_link

def _dynamic_build_derivation_impl(actions, artifacts, dynamic_values, outputs, arg):
    json_drvs = artifacts[arg.drv_json].read_json()
    json_ghc = artifacts[arg.ghc_info].read_json()
    ghc_version = json_ghc["version"]

    # note, this output is never used
    actions.write(outputs[arg.out].as_output(), "")

    def get_outputs(info: list[str] | dict[str, typing.Any]):
        """Get outputs for `inputDrvs`, regardless of the nix version that produced the information.

        In older nix versions, the information was just a list of strings, in newer versions it is
        a dict having a `outputs` field (and a `dynamicOutputs` field).
        """
        if isinstance(info, list):
            return info
        else:
            return info["outputs"]

    toolchain_libs = {
        drv: {
            "name": info["env"]["pname"],
            "output": info["outputs"]["out"]["path"],
            "deps": [dep for dep, outputs in info["inputDrvs"].items() if "out" in get_outputs(outputs) and dep in json_drvs]
        }
        for drv, info in json_drvs.items()
    }

    deps = {}
    pkgs = {}
    package_conf_dir = "lib/ghc-{}/lib/package.conf.d".format(ghc_version)

    for drv in post_order_traversal({k: v["deps"] for k, v in toolchain_libs.items()}):
        drv_info = toolchain_libs[drv]
        name = drv_info["name"]
        this_pkg_deps = [
            pkgs[toolchain_libs[drv_dep]["name"]]
            for drv_dep in drv_info["deps"]
        ]
        deps[drv] = __nix_build_drv(
            actions,
            package = name,
            drv = drv,
            deps = [deps[dep] for dep in drv_info["deps"]],
        )

        pkgs[name] = actions.tset(
            HaskellPackageDbTSet,
            value = HaskellPackage(db = cmd_args(deps[drv], package_conf_dir, delimiter="/"), path = deps[drv]),
            children = this_pkg_deps,
        )

    return [DynamicHaskellPackageDbInfo(packages = pkgs)]

_dynamic_build_derivation = dynamic_actions(impl = _dynamic_build_derivation_impl)

def _build_packages_info(ctx: AnalysisContext, ghc: RunInfo, ghc_pkg: RunInfo) -> DynamicValue:
    nix_drv_json_script = ctx.attrs._nix_drv_json_script[RunInfo]

    flake = ctx.attrs.flake

    drv_json = ctx.actions.declare_output("drv.json")

    cmd = cmd_args(nix_drv_json_script, "--output", drv_json.as_output(), "--flake", cmd_args("path:", flake, "#haskellPackages", delimiter=""))

    ctx.actions.run(
        cmd,
        category = "nix_drv",
        local_only = True,
    )

    ghc_info = ctx.actions.declare_output("ghc_info.json")
    ctx.actions.run(
        cmd_args("bash", "-ec", '''printf '{ "version": "%s" }\n' "$( $1 --numeric-version )" > "$2" ''', "--", ghc, ghc_info.as_output()),
        category = "ghc_info",
        local_only = True,
    )

    # a dynamic action *must* have an output
    out = ctx.actions.declare_output("bogus")

    dyn_pkgs_info = ctx.actions.dynamic_output_new(_dynamic_build_derivation(
        dynamic = [drv_json, ghc_info],
        outputs = [out.as_output()],
        arg = struct(
            ghc_info = ghc_info,
            drv_json = drv_json,
            out = out,
        ),
    ))

    return dyn_pkgs_info

def _nix_haskell_toolchain_impl(ctx: AnalysisContext) -> list[Provider]:
    ghc = ctx.attrs.ghc[RunInfo]
    ghc_pkg = ctx.attrs.ghc_pkg[RunInfo]

    return [
        DefaultInfo(),
        HaskellToolchainInfo(
            compiler = ghc,
            packager = ghc_pkg,
            linker = ghc,
            haddock = ctx.attrs.haddock[RunInfo],
            compiler_flags = ctx.attrs.compiler_flags,
            linker_flags = ctx.attrs.linker_flags,
            ghci_script_template = ctx.attrs._ghci_script_template,
            ghci_iserv_template = ctx.attrs._ghci_iserv_template,
            script_template_processor = ctx.attrs._script_template_processor,
            packages = HaskellPackagesInfo(dynamic = _build_packages_info(ctx, ghc, ghc_pkg)),
        ),
        HaskellPlatformInfo(
            name = host_info().arch,
        ),
    ]

nix_haskell_toolchain = rule(
    impl = _nix_haskell_toolchain_impl,
    attrs = {
        "_ghci_script_template": attrs.source(default = "//:ghci_script_template"),
        "_ghci_iserv_template": attrs.source(default = "//:ghci_iserv_template"),
        "_script_template_processor": attrs.dep(
            providers = [RunInfo],
            default = "prelude//haskell/tools:script_template_processor",
        ),
        "_nix_drv_json_script": attrs.dep(
            providers = [RunInfo],
            default = "//:nix_drv_json",
        ),
        "compiler_flags": attrs.list(
            attrs.string(),
            default = [],
        ),
        "linker_flags": attrs.list(
            attrs.string(),
            default = [],
        ),
        "ghc": attrs.dep(
            providers = [RunInfo],
            default = "//:ghc",
        ),
        "ghc_pkg": attrs.dep(
            providers = [RunInfo],
            default = "//:ghc[ghc-pkg]",
        ),
        "haddock": attrs.dep(
            providers = [RunInfo],
            default = "//:haddock",
        ),
        "flake": attrs.source(allow_directory = True),
    },
    is_toolchain_rule = True,
)
