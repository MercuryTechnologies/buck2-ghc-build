# Work around for some odd behaviour where we can't codesign a file
# in-place if it has been called before. This happens for example if
# you try to fix-up a binary using strip/install_name_tool, after it
# had been used previous.  The solution is to copy the binary (with
# the corrupted signature from strip/install_name_tool) to some
# location, sign it there and move it back into place.
#
# This does not appear to happen with the codesign tool that ships
# with recent macOS BigSur installs on M1 arm64 machines.  However it
# had also been happening with the tools that shipped with the DTKs.

signWithGetTaskAllow() {
    local tmpdir
    tmpdir=$(mktemp -d)

    # NOTE: this function is modified from the nixpkgs version with an
    # additional entitlement: get-task-allow.

    cat <<-EOF > "$tmpdir/entitlements"
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	  <key>com.apple.security.get-task-allow</key>
	  <true/>
	</dict>
	</plist>
	EOF

    local file="$1"
    cp "$file" "$tmpdir"
    CODESIGN_ALLOCATE=@codesignAllocate@ \
        @sigtool@/bin/codesign -f --entitlements "$tmpdir/entitlements" -s - "$tmpdir/$(basename "$file")"
    mv "$tmpdir/$(basename "$file")" "$file"
    rm "$tmpdir/entitlements"
    rmdir "$tmpdir"
}

signIfRequired() {
    local file=$1
    if @sigtool@/bin/sigtool --file "$file" check-requires-signature; then
        signWithGetTaskAllow "$file"
    fi
}
