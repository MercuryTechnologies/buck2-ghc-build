# buck2-ghc-build

Building GHC HEAD with buck2 toolchain.

## Getting started

Enter the shell.
```
$ nix develop
```
Set the environment variables. Examples in `myenv.sh.iwkim-mac`.
```
$ source myenv.sh.iwkim-mac
```

Then, build (a part of) GHC.
```
$ buck2 build //ghc-build:ghc-internal
```
