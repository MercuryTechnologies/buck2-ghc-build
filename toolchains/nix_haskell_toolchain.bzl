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

def __nix_build_drv(ctx: AnalysisContext, drv: str, package: str, output, deps) -> Artifact:
    # calls nix build /path/to/file.drv^*

    out_link = ctx.actions.declare_output(package, "out.link")
    nix_build = cmd_args([
        "bash",
        "-ec",
        '''
        if [[ -e "$1" ]]; then
          nix-store --add-root "$2" -r "$1"
        else
          nix build --out-link "$2" "$3"
        fi
        ''',
        "--",
        output,
        out_link.as_output(),
        cmd_args(drv, format = "{}^*"),
    ], hidden = deps)
    ctx.actions.run(nix_build, category = "nix_build", identifier = package, local_only = True)

    return out_link

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


def _build_package_db(ctx: AnalysisContext, ghc: RunInfo, ghc_pkg: RunInfo) -> (Artifact, DynamicValue):
    pkg_db = ctx.actions.declare_output("db", dir = True)

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

    def create_pkg_dbs(ctx, artifacts, _resolved, outputs, json = drv_json, package_dbs=package_dbs, ghc_info=ghc_info):
        json_drvs = artifacts[json].read_json()
        json_ghc = artifacts[ghc_info].read_json()

        ghc_version = json_ghc["version"]

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
        for drv in post_order_traversal({k: v["deps"] for k, v in toolchain_libs.items()}):
            drv_info = toolchain_libs[drv]
            name = drv_info["name"]
            this_pkg_deps = [
                pkgs[toolchain_libs[drv_dep]["name"]]
                for drv_dep in drv_info["deps"]
            ]
            deps[drv] = __nix_build_drv(
                ctx,
                package = name,
                drv = drv,
                output = drv_info["output"],
                deps = [deps[dep] for dep in drv_info["deps"]],
            )

            requested_db = package_dbs.get(name)
            output_db = outputs[requested_db] if requested_db else ctx.actions.declare_output(name, "db")

            _build_pkg_db(
                ctx,
                ghc_pkg,
                ghc_version,
                packages = [deps[drv]],
                identifier = name,
                output = output_db,
            )

            pkgs[name] = ctx.actions.tset(
                HaskellPackageDbTSet,
                value = HaskellPackage(db = output_db, path = deps[drv]),
                children = this_pkg_deps,
            )

        # some libraries come with GHC, so there is no separate haskell package for them
        lib_names = [ drv["name"] for drv in toolchain_libs.values() ]
        builtin_libs = [ output for name, output in package_dbs.items() if name not in lib_names ]

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
            deps.values(),
            output = outputs[pkg_db],
        )

        return [DynamicHaskellPackageDbInfo(packages = pkgs)]

    dyn_pkgs_info = ctx.actions.dynamic_output(
        dynamic = [drv_json, ghc_info],
        promises = [],
        inputs = [],
        outputs = [pkg_db.as_output()] + [db.as_output() for db in package_dbs.values()],
        f = create_pkg_dbs,
    )

    return pkg_db, dyn_pkgs_info

def _nix_haskell_toolchain_impl(ctx: AnalysisContext) -> list[Provider]:
    ghc = ctx.attrs.ghc[RunInfo]
    ghc_pkg = ctx.attrs.ghc_pkg[RunInfo]

    pkg_db, dynamic = _build_package_db(ctx, ghc, ghc_pkg)

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
            packages = HaskellPackagesInfo(package_db = pkg_db, dynamic = dynamic),
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
