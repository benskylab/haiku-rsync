#!/bin/bash
# Native rsync 3.5.1 package build for Haiku OS (x86_64)
# Runs entirely on the Haiku machine.
#
# Produces: /boot/home/out/rsync-3.5.1-1-x86_64.hpkg
#
# The patch (Haiku xattr support + socket/getpass/getxattr linkage + MAKEDEV
# workaround) is applied to configure.ac / rsync.h before this script runs.
set -e

VERSION="3.5.1"
REVISION="1"
PKGVER="${VERSION}-${REVISION}"
SRC="/boot/home/build/rsync-3.5.1"
OUT="/boot/home/out"
STAGE="/boot/home/build/stage-rsync"
PKGNAME="rsync"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT"

cd "$SRC"

# Install into a staging root. make install places files under
# $DESTDIR/boot/system/... -- Haiku packages store paths relative to the
# system dir, so we re-root them to $STAGE/{bin,share,...}.
rm -rf /tmp/rsync-destroot
make install DESTDIR=/tmp/rsync-destroot >/dev/null
mkdir -p "$STAGE"
cp -a /tmp/rsync-destroot/boot/system/. "$STAGE/"
rm -rf /tmp/rsync-destroot

# Haiku's man(1) (mandoc) only reads /boot/system/documentation/man --
# the hand flow configures with upstream defaults (share/man), so
# re-root the pages (share/locale, if any, stays put). No-op if the
# tree was configured with --mandir already.
if [ -d "$STAGE/share/man" ]; then
	mkdir -p "$STAGE/documentation"
	mv "$STAGE/share/man" "$STAGE/documentation/man"
	rmdir "$STAGE/share" 2>/dev/null || true
fi

# Strip the binary to shrink the package; keep a debug copy for a
# separate debuginfo package.
mkdir -p "$OUT/debuginfo"
cp "$STAGE/bin/rsync" "$OUT/debuginfo/rsync.debug"
strip "$STAGE/bin/rsync"

# rsync-ssl is a shell script; ensure it is executable.
chmod 755 "$STAGE/bin/rsync-ssl"

# ---- .PackageInfo ----
cat > "$STAGE/.PackageInfo" <<EOF
name			$PKGNAME
version			$PKGVER
architecture		x86_64
summary			"A fast incremental file transfer utility"
description		"rsync is a file transfer program using the 'rsync algorithm' which provides a very fast method for bringing remote files into sync. It does this by sending just the differences across the link, without requiring that both sets of files be present at one end beforehand. This build is compiled natively for Haiku with support for xxhash/zstd/lz4/zlib compression, extended attributes, and the rsync daemon and SSH transports."
packager		"Native rsync for Haiku build"
vendor			"rsync project (rsync.samba.org)"
licenses {
	"GNU GPL v3"
}
copyrights {
	"1996-2026 Andrew Tridgell, Wayne Davison, and others"
}
provides {
	$PKGNAME = $PKGVER compat >= 3
	cmd:rsync = $PKGVER
	cmd:rsync_ssl = $PKGVER
}
requires {
	haiku >= r1~beta5
	lib:libcrypto >= 3
	lib:liblz4 >= 1
	lib:libxxhash
	lib:libzstd >= 1
	lib:libz >= 1
}
urls {
	"https://rsync.samba.org/"
}
EOF

# ---- create the package from the staged tree ----
cd "$STAGE"
rm -f "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"
package create -C "$STAGE" "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"

echo "=== package created ==="
ls -la "$OUT"/*.hpkg
package info "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"
echo "=== contents ==="
package list "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"
