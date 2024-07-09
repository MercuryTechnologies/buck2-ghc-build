#!/usr/bin/env bash
set -euo pipefail

check_env_var() {
    local name="$1"
    if [[ -z "${!name}" ]]; then
	echo "The variable '$name' is not set or empty." >&2
	return 1
    fi
    echo "${!name}"
}

check_executable() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
	echo "The file '$path' does not exist." >&2
	return 1
    fi
    if [[ ! -x "$path" ]]; then
	echo "The file '$path' is not executable." >&2
	return 1
    fi
    echo "$(realpath -s "$path")"
}

error() {
    echo 'Failed to discover the external Haskell compiler. Be sure to enter `nix develop .#buck2` and check that `$GHC_PATH`, `$GHC` and `$GHC_PKG_DB` are set.' >&2
}

trap error ERR

path="$(check_env_var GHC_PATH)"
ghc="$(check_env_var GHC)"

IFS=":" read -r -a ghc_pkg_db <<< "$(check_env_var GHC_PKG_DB)"

ghc_pkg="$(dirname "$ghc")/ghc-pkg"
haddock="$(dirname "$ghc")/haddock"

check_executable "$ghc"
check_executable "$ghc_pkg"
check_executable "$haddock"

ghc_out="$1"
ghc_pkg_out="$2"
haddock_out="$3"

make_wrapper() {
    local orig="$1"
    local wrapper="$2"
    cat >"$wrapper" <<EOF
#!$BASH
set -euo pipefail
export PATH="$path:\$PATH"
exec "$orig" "\$@"
EOF
    chmod +x "$wrapper"
}

make_ghc_wrapper() {
    local orig="$1"
    local wrapper="$2"
    local dbstr=""
    for db in "${ghc_pkg_db[@]}"
    do
       dbstr+="-package-db $db "
    done
    #return 1
    cat >"$wrapper" <<EOF
#!$BASH
set -euo pipefail
export PATH="$path:\$PATH"
exec "$orig" "$dbstr" "\$@"
EOF
    chmod +x "$wrapper"
}

make_ghc_wrapper "$ghc" "$ghc_out"
make_wrapper "$ghc_pkg" "$ghc_pkg_out"
make_wrapper "$haddock" "$haddock_out"
