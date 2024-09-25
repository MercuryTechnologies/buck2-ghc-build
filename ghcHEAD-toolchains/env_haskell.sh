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
    echo 'Failed to discover the external Haskell compiler. Be sure to enter `nix develop .#buck2` and check that `$GHC_PATH`, `$GHC`, `$GHC_PKG`, `$HADDOCK`, `$GHC_PKG_DB`, `$GHC_EXTRA_OPTS` and `$GHC_LD_LIBRARY_PATH` are set.' >&2
}

trap error ERR

path="$(check_env_var GHC_PATH)"
ghc="$(check_env_var GHC)"
ghc_pkg="$(check_env_var GHC_PKG)"
haddock="$(check_env_var HADDOCK)"
ghc_persistent_worker_socket="$(check_env_var GHC_PERSISTENT_WORKER_SOCKET)"
#ghc_pkg="$(dirname "$ghc")/ghc-pkg"
#haddock="$(dirname "$ghc")/haddock"

ghc_ld_library_path="$(check_env_var GHC_LD_LIBRARY_PATH)"
IFS=":" read -r -a ghc_pkg_db <<< "$(check_env_var GHC_PKG_DB)"
IFS=":" read -r -a ghc_extra_opts <<< "$(check_env_var GHC_EXTRA_OPTS)"

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
    local dbstr=()
    for db in "${ghc_pkg_db[@]}"
    do
        dbstr+=('-package-db')
        dbstr+=("'$db'")
    done
    local optstr=()
    for opt in "${ghc_extra_opts[@]}"
    do
        optstr+=("'$opt'")
    done
    cat >"$wrapper" <<EOF
#!$BASH
set -euo pipefail
export PATH="$path:\$PATH"
export LD_LIBRARY_PATH="$ghc_ld_library_path"
export DYLD_LIBRARY_PATH="$ghc_ld_library_path"
#export DYLD_PRINT_LIBRARIES=1
export GHC_PERSISTENT_WORKER_SOCKET="$ghc_persistent_worker_socket"
exec "$orig" ${dbstr[@]} ${optstr[@]} "\$@"
EOF
    chmod +x "$wrapper"
}

make_ghc_wrapper "$ghc" "$ghc_out"
make_wrapper "$ghc_pkg" "$ghc_pkg_out"
make_wrapper "$haddock" "$haddock_out"
