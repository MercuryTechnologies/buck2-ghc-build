load(
    "@prelude//haskell:toolchain.bzl",
    "DynamicHaskellPackageDbInfo",
    "HaskellPackage",
    "HaskellPackageDbTSet",
    "HaskellPackagesInfo",
    "HaskellPlatformInfo",
    "HaskellToolchainInfo",
)
load("@prelude//utils:graph_utils.bzl", "post_order_traversal")
load(":nix.bzl", "NixPathInfo")

NixDerivationInfo = record(
    derivation = NixPathInfo,
    outputs = dict[str, NixPathInfo],
)

DynamicHaskellNixInfo = provider(fields = {
    "packages": dict[str, NixDerivationInfo],
})

def __nix_build_drv(
        actions,
        nix_wrapper: RunInfo,
        nix_config: dict[str, str | list[str]],
        drv: str,
        package: str,
        deps) -> Artifact:
    # calls nix build /path/to/file.drv^*

    command = cmd_args(nix_wrapper, hidden = deps)
    out_link = actions.declare_output(package, "out.link")

    for name, value in nix_config.items():
        if isinstance(value, list):
            value = " ".join(value)
        command.add(["--option", name, value])

    nix_build = command.add([
        "build",
        "--print-build-logs",
        cmd_args(drv, format = "{}^*"),
        "--buck2-output",
        out_link.as_output(),
    ])
    actions.run(nix_build, category = "nix_build", identifier = package, local_only = True)

    return out_link

def _dynamic_build_derivation_impl(actions, arg, drv_json, ghc_info, nix_config_json):
    json_drvs = drv_json.read_json()
    json_ghc = ghc_info.read_json()
    ghc_version = json_ghc["version"]
    nix_config = nix_config_json.read_json()

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
            "deps": [dep for dep, outputs in info["inputDrvs"].items() if "out" in get_outputs(outputs) and dep in json_drvs],
        }
        for drv, info in json_drvs.items()
    }

    deps = {}
    pkgs = {}
    nix_pkgs = {}
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
            arg.nix_wrapper,
            nix_config,
            package = name,
            drv = drv,
            deps = [deps[dep] for dep in drv_info["deps"]],
        )

        pkgs[name] = actions.tset(
            HaskellPackageDbTSet,
            value = HaskellPackage(db = cmd_args(deps[drv], package_conf_dir, delimiter = "/"), path = deps[drv]),
            children = this_pkg_deps,
        )

        outputs = {}
        outputs["out"] = NixPathInfo(path = json_drvs[drv]["outputs"]["out"]["path"])
        if "hie" in json_drvs[drv]["outputs"]:
            outputs["hie"] = NixPathInfo(path = json_drvs[drv]["outputs"]["hie"]["path"])
        if "doc" in json_drvs[drv]["outputs"]:
            outputs["doc"] = NixPathInfo(path = json_drvs[drv]["outputs"]["doc"]["path"])
        nix_pkgs[name] = NixDerivationInfo(
            derivation = NixPathInfo(path = drv),
            outputs = outputs,
        )

    return [
        DynamicHaskellPackageDbInfo(packages = pkgs),
        DynamicHaskellNixInfo(packages = nix_pkgs),
    ]

_dynamic_build_derivation = dynamic_actions(
    impl = _dynamic_build_derivation_impl,
    attrs = {
        "arg": dynattrs.value(typing.Any),
        "drv_json": dynattrs.artifact_value(),
        "ghc_info": dynattrs.artifact_value(),
        "nix_config_json": dynattrs.artifact_value(),
    },
)

def _make_drv_json(ctx: AnalysisContext, name: str) -> Artifact:
    nix_drv_json_script = ctx.attrs._nix_drv_json_script[RunInfo]
    flake = ctx.attrs.flake

    drv_json = ctx.actions.declare_output(name)

    cmd = cmd_args(nix_drv_json_script, "--output", drv_json.as_output(), "--flake", cmd_args("path:", flake, "#haskellPackages", delimiter = ""))

    ctx.actions.run(
        cmd,
        category = "nix_drv",
        local_only = True,
    )
    return drv_json

def _make_ghc_info(ctx: AnalysisContext, ghc: RunInfo) -> Artifact:
    ghc_info = ctx.actions.declare_output("ghc_info.json")
    ctx.actions.run(
        cmd_args("bash", "-ec", '''printf '{ "version": "%s" }\n' "$( $1 --numeric-version )" > "$2" ''', "--", ghc, ghc_info.as_output()),
        category = "ghc_info",
        local_only = True,
    )
    return ghc_info

def _get_nix_config(ctx: AnalysisContext) -> Artifact:
    nix_config_json = ctx.actions.declare_output("nix_conf.json")
    flake = ctx.attrs.flake
    ctx.actions.run(
        cmd_args("bash", "-ec", '''nix eval --json --apply 'f: f.nixConfig or {}' --file "$1/flake.nix" > "$2" ''', "--", flake, nix_config_json.as_output()),
        category = "nix_config",
        local_only = True,
    )
    return nix_config_json

def _build_packages_info(ctx: AnalysisContext, drv_json: Artifact, ghc_info: Artifact, nix_config_json: Artifact) -> DynamicValue:
    dyn_pkgs_info = ctx.actions.dynamic_output_new(_dynamic_build_derivation(
        arg = struct(
            nix_wrapper = ctx.attrs._nix_wrapper[RunInfo],
        ),
        ghc_info = ghc_info,
        drv_json = drv_json,
        nix_config_json = nix_config_json,
    ))

    return dyn_pkgs_info

def truthy(value: str) -> bool:
    return value.lower() in ["true", "yes", "on"]

config_worker_enable = truthy(read_config("ghc-worker", "enable", "false"))
config_worker_make = truthy(read_config("ghc-worker", "make", "false"))
config_worker_single = truthy(read_config("ghc-worker", "single", "false"))

def _nix_haskell_toolchain_impl(ctx: AnalysisContext) -> list[Provider]:
    ghc = ctx.attrs.ghc[RunInfo]
    ghc_pkg = ctx.attrs.ghc_pkg[RunInfo]

    drv_json = _make_drv_json(ctx, "drv.json")
    ghc_info = _make_ghc_info(ctx, ghc)
    nix_config_json = _get_nix_config(ctx)

    # TODO this is used for compatibility with the local-GHC feature of the worker, where we don't have a wrapper script
    # that provides the `-B` option like in nixpkgs GHCs.
    # There are probably much better solutions, which I'll leave to the experts.
    ghc_dir = ctx.actions.declare_output("ghc_dir")
    ctx.actions.run(
        cmd_args("bash", "-ec", '''$1 --print-libdir > "$2" ''', "--", ghc, ghc_dir.as_output()),
        category = "ghc_dir_info",
        local_only = True,
    )

    sub_targets = {}
    sub_targets["drv_json"] = [DefaultInfo(default_outputs = [drv_json])]
    sub_targets["ghc_info"] = [DefaultInfo(default_outputs = [ghc_info])]
    sub_targets["ghc_dir"] = [DefaultInfo(default_outputs = [ghc_dir])]

    return [
        DefaultInfo(
            sub_targets = sub_targets,
        ),
        HaskellToolchainInfo(
            compiler = ghc,
            ghc_dir = ghc_dir,
            packager = ghc_pkg,
            linker = ghc,
            haddock = ctx.attrs.haddock[RunInfo],
            compiler_flags = ctx.attrs.compiler_flags,
            linker_flags = ctx.attrs.linker_flags,
            ghci_script_template = ctx.attrs._ghci_script_template,
            ghci_iserv_template = ctx.attrs._ghci_iserv_template,
            script_template_processor = ctx.attrs._script_template_processor,
            packages = HaskellPackagesInfo(dynamic = _build_packages_info(ctx, drv_json, ghc_info, nix_config_json)),
            use_worker = config_worker_enable,
            worker_make = config_worker_make,
            worker_single = config_worker_single,
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
        "_nix_wrapper": attrs.dep(
            providers = [RunInfo],
            default = "//tools:nix_wrapper",
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
