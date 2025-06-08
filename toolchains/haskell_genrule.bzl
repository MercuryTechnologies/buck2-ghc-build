def _haskell_genrule_impl(ctx: AnalysisContext) -> list[Provider]:
    script = cmd_args(ctx.attrs.cmd)
    run_info = RunInfo(args = script)
    return [DefaultInfo(), run_info]

haskell_genrule = rule(
    impl = _haskell_genrule_impl,
    attrs = {
        "srcs": attrs.list(attrs.source(), default = []),
        "out": attrs.string(),
        "cmd": attrs.option(attrs.arg(), default = None),
    },
)