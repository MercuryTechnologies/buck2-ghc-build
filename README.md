# buck2-ghcHEAD

Buck2 project template supporting both nix-based GHC env and custom.

## Getting started

This build template supports two build toolchain. One is GHC compiler and libraries configured via Nix,
and the other is those prepared externally (custom GHC). For the latter, the environment variables `GHC`, `GHC_PATH`,
`GHC_PKG_DB` and `GHC_EXTRA_OPTS` are used for specifying the locations of external tools and package configuration.

For nix-based GHC mode, enter the shell by
```
$ nix develop .#buck2-nix
```

For custom GHC mode, enter the shell by
```
$ nix develop .#buck2-ghcHEAD
```
and set the environmental variables. For example,
```
$ export GHC_PATH=/nix/store/943sxl4vcfpfg6xaagxvgwbgz9scl7lc-coreutils-9.3/bin:/nix/store/m488d5iwzn93bdk1j5gxl77k3zb8y285-cctools-binutils-darwin-wrapper-11.1.0-973.0.1/bin:/nix/store/n6s41h0vwcllawzpxbmhxkbla4lhj9va-cctools-llvm-11.1.0-973.0.1/bin
$ export GHC=~/repo/srcc/ghcHEAD/_build/stage1/bin/ghc
$ export GHC_PKG_DB=~/.local/state/cabal/store/ghc-9.11.20240625/package.db
$ export GHC_EXTRA_OPTS="-L/nix/store/cmxms1ix9ki9n5x7wkgilrhbcq97b48z-gmp-with-cxx-6.3.0/lib"
```
Note that one can specify multiple `package.db` locations by colon-separated list in the `GHC_PKG_DB` variable.

## Build

```
$ buck2 build //myproject:pkg-b[static]
```

To build a specific target and show which output was generated for it
```
$ buck2 build //myproject:pkg-b --show-output
```

To show compiler output during the build
```
$ buck2 build //myproject:pkg-b -v 2,stderr
```

## Documentation

Read the documentation on the [Buck2 website][buck2] for detailed documentation.
In particular:
- https://buck2.build/docs/users/cheat_sheet/
- https://buck2.build/docs/users/faq/common_issues/
- https://buck2.build/docs/concepts/key_concepts/

[buck2]: https://buck2.build/

## Haskell toolchain libraries

Libraries provided by nix need to be added to the `ghcWithPackages` call in order to make them available for the compiler, and they need
to be added to the `toolchain_libraries` list for buck2 to make them available as `//haskell:lib-name` targets.

In order to add a new toolchain library from nix:

1. add it to the `deps` attribute of a `haskell_library` or `haskell_binary` target by referring to `//haskell:foo`

    ```bzl
    haskell_library(
       name = "mylib",
       deps = [ "//haskell:foo", ... ],
    )
    ```
2. run `buck2 bxl haskell/toolchain.bxl:libs`
3. commit the changes to `toolchains/libs.bzl` and `toolchains/nix/ghc-toolchain-libraries.nix`

## Update buck2

Run the following command and commit the changed files in `nix/overlays/buck2`:

```
$ nix run '.#buck2-update'
```

## Query

See the [Buck2 cheat sheet][buck2-cheat] for common cases and the [Buck2 query
docs][buck2-query] for further details.

[buck2-cheat]: https://buck2.build/docs/users/cheat_sheet/
[buck2-query]: https://buck2.build/docs/users/query/cquery/

List the sub-targets available under a given target
```
$ buck2 audit subtargets //myproject:pkg-b
```

Show the attributes of a given target
```
$ buck2 uquery //myproject:pkg-b -A
```

List the providers of a given target in detail
```
$ buck2 audit providers //myproject:pkg-b
```

Visualize the dependency graph of a target
```
$ buck2 cquery 'deps(backend) ^ //myproject/...' --dot | xdot -
```

Query the build actions that will be performed to build a given target
```
$ buck2 aquery \
    'kind(run, deps(//myproject:pkg-b))' \
    --output-attribute='cmd|category'
```

## Debug

If the build failed, understand which command failed
```
$ buck2 log what-failed
```

Understand what build commands were executed
```
$ buck2 log what-ran
```

Print commands that ran including their output
```
$ buck2 log what-ran --show-std-err --format json | jq
```

Replay the Buck2 terminal output
```
$ buck2 log replay
```

Display the logs for the recent n-th build
```
$ buck2 log replay --recent 0
```

Display the logs for a specific build ID
```
$ buck2 log replay --trace-id ff7a9c37-7637-4c98-9c39-9ef51d5f824b
```

Extract exit code and output of all build actions
```
$ buck2 log show | jq -r '
    .Event.data.SpanEnd.data.ActionExecution
    | try .commands[]
    | ( "exit: " + (.details.signed_exit_code|tostring)
      + "\nstdout:\n" + .details.stdout
      + "\nstderr:\n" + .details.stderr
      )
  '
```

Extract build commands from the log
```
$ buck2 log show | jq -r '
    .Event.data.SpanStart.data.ExecutorStage.stage.Local.stage.Execute.command.argv
  | try join(" ")
  '
```

See [Buck2 Logging documentation][buck2-logging] for further information.

[buck2-logging]: https://buck2.build/docs/users/build_observability/logging/

## Profile and Optimize

Display the critical path
```
$ buck2 log critical-path
```

Generate a Chrome trace viewable in [Perfetto UI][perfetto] or similar.
```
$ buck2 debug chrome-trace --trace-path=OUT.json
```

[Perfetto UI supports SQL queries][perfetto-sql] that can be used to analyze
the performance of specific types of actions. However, one must be careful to
separate the actual execution time from any potential time spent in the queue.

The following query accumulates all the (dynamic) Haskell module compile
actions that executed locally.
```sql
SELECT AVG(exec_slice.dur), SUM(exec_slice.dur)
FROM slice as exec_slice
INNER JOIN slice as parent_slice ON exec_slice.parent_id = parent_slice.id
WHERE exec_slice.name = "local_execute" AND parent_slice.name LIKE "%haskell_compile_shared%"
```

See [Buck2 Observability and Optimization][buck2-opt] for information on
profiling Buck2 and its rules themselves.

[perfetto]: https://ui.perfetto.dev/
[perfetto-sql]: https://perfetto.dev/docs/quickstart/trace-analysis
[buck2-opt]: https://buck2.build/docs/rule_authors/optimization/
