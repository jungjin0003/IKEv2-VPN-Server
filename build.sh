#!/usr/bin/env bash
#
# Unified build script for the IKEv2VPN Synology package (.spk).
#
# It performs two stages, in order:
#   1. (optional) Build the bundled static strongSwan from source and place
#      the minimal runtime files (charon, swanctl, strongswan.d/charon/*.conf)
#      into src/package/strongswan/.
#   2. Assemble the DSM .spk from src/ into dist/.
#
# Stage 1 is SKIPPED automatically when a prebuilt strongSwan is already
# present under src/package/strongswan/. Pass --rebuild-strongswan to force a
# fresh build from source.
#
# strongSwan is built --disable-shared --enable-static --enable-monolithic
# (no plugin .so files - everything baked into charon/swanctl) and links
# libgmp dynamically against the build machine's system libgmp.
#
# Usage:
#   ./build.sh                       # build strongSwan if needed, then the .spk
#   ./build.sh --spk-only            # only assemble the .spk; never compile
#                                    #   (requires a prebuilt strongSwan; this
#                                    #    is the mode build.ps1 uses on Windows)
#   ./build.sh --rebuild-strongswan  # force a fresh strongSwan build from source
#   ./build.sh -v 6.0.7              # pin the strongSwan source version to build
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------- arguments
VERSION="latest"
SPK_ONLY=false
REBUILD_SS=false
while [ $# -gt 0 ]; do
	case "$1" in
	-v | --version) VERSION="$2"; shift 2 ;;
	-v=* | --version=*) VERSION="${1#*=}"; shift ;;
	--spk-only) SPK_ONLY=true; shift ;;
	--rebuild-strongswan) REBUILD_SS=true; shift ;;
	-h | --help)
		grep -E '^#( |$)' "$0" | sed -e 's/^#//' -e 's/^ //'
		exit 0 ;;
	*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done

# -------------------------------------------------------------------- paths
SRC="$ROOT/src"
SS_DIR="$SRC/package/strongswan"                 # bundled strongSwan (SPK source of truth)
SS_CHARON="$SS_DIR/libexec/ipsec/charon"
SS_SWANCTL="$SS_DIR/sbin/swanctl"
SS_CONFDIR="$SS_DIR/strongswan.d/charon"

STAGE="$ROOT/build/stage"                        # .spk staging area
DIST="$ROOT/dist"

# strongSwan source-build install layout (compiled-in --prefix etc.)
PREFIX=/var/packages/IKEv2VPN/target/strongswan
SYSCONFDIR=/var/packages/IKEv2VPN/etc
SWANCTLDIR=/var/packages/IKEv2VPN/etc/swanctl
PIDDIR=/var/packages/IKEv2VPN/var
SS_STAGE="$ROOT/build/strongswan-stage"          # DESTDIR for 'make install'

# ------------------------------------------------------------------ helpers
log()  { printf '\n\033[1;32m[*] %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$1" >&2; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$1" >&2; exit 1; }

require_tool() { command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1"; }

# true when the minimal runtime files are already present under src/
have_prebuilt() {
	[ -f "$SS_CHARON" ] && [ -f "$SS_SWANCTL" ] && ls "$SS_CONFDIR"/*.conf >/dev/null 2>&1
}

# --------------------------------------------------- stage 1: strongSwan
build_strongswan() {
	$SPK_ONLY && die "No prebuilt strongSwan available and --spk-only was given. Build strongSwan first on Linux with: ./build.sh"

	require_tool gcc
	require_tool make
	require_tool curl
	require_tool tar
	require_tool strip
	if [ ! -f /usr/include/gmp.h ] && [ ! -f /usr/include/x86_64-linux-gnu/gmp.h ]; then
		die "libgmp-dev (gmp.h) not found. Install it, e.g. 'sudo apt-get install libgmp-dev'."
	fi

	if [ "$VERSION" = "latest" ]; then
		_srctar="strongswan.tar.bz2"
	else
		_srctar="strongswan-${VERSION}.tar.bz2"
	fi
	_url="https://download.strongswan.org/${_srctar}"
	_dl="$ROOT/build/strongswan-src.tar.bz2"
	mkdir -p "$ROOT/build"

	log "Downloading strongSwan source ($_url)"
	curl -fL --retry 3 -o "$_dl" "$_url"

	# Capture the whole listing rather than `tar tjf | head -n1`: under
	# `set -o pipefail`, head closing the pipe early makes tar exit via
	# SIGPIPE, which aborts the whole script right after the download (this
	# was a real bug - build.sh appeared to "only download and stop").
	_listing="$(tar tjf "$_dl")"
	_first="${_listing%%$'\n'*}"
	_dirname="${_first%%/*}"
	_ver="${_dirname#strongswan-}"
	_srcdir="$ROOT/build/$_dirname"

	log "Extracting strongSwan source (version: $_ver)"
	rm -rf "$_srcdir"
	tar xjf "$_dl" -C "$ROOT/build"
	rm -f "$_dl"

	SS_CFLAGS="${CFLAGS:-} -march=x86-64 -O2"
	log "Configuring strongSwan (CFLAGS: $SS_CFLAGS)"
	(
		cd "$_srcdir"
		make distclean >/dev/null 2>&1 || true
		CFLAGS="$SS_CFLAGS" ./configure \
			--prefix="$PREFIX" \
			--sysconfdir="$SYSCONFDIR" \
			--with-swanctldir="$SWANCTLDIR" \
			--with-piddir="$PIDDIR" \
			--disable-shared --enable-static --enable-monolithic \
			--enable-charon \
			--enable-ikev2 --disable-ikev1 \
			--enable-gmp --enable-random --enable-nonce --enable-hmac \
			--enable-sha1 --enable-sha2 --enable-md5 --enable-md4 --enable-fips-prf \
			--enable-aes --enable-des --enable-gcm \
			--enable-x509 --enable-pubkey --enable-pkcs1 --enable-pkcs8 --enable-pem \
			--enable-eap-identity --enable-eap-mschapv2 --enable-eap-radius --enable-eap-tls \
			--enable-kernel-netlink --enable-socket-default --enable-updown --enable-attr \
			--enable-vici --enable-swanctl \
			--disable-defaults

		log "Compiling strongSwan (serial build, -j1, to avoid build races)"
		make -j1

		log "Installing to staging (DESTDIR=$SS_STAGE)"
		rm -rf "$SS_STAGE"
		mkdir -p "$SS_STAGE"
		make install -j1 DESTDIR="$SS_STAGE"
	)

	_charon="$SS_STAGE$PREFIX/libexec/ipsec/charon"
	_swanctl="$SS_STAGE$PREFIX/sbin/swanctl"
	_confdir="$SS_STAGE$SYSCONFDIR/strongswan.d/charon"

	log "Verifying build (monolithic, libgmp linkage)"
	if find "$SS_STAGE$PREFIX" -name '*.so*' | grep -q .; then
		find "$SS_STAGE$PREFIX" -name '*.so*' >&2
		die "strongSwan plugins were built as separate .so files (not monolithic)."
	fi
	for _b in "$_charon" "$_swanctl"; do
		file "$_b"
		ldd "$_b" | grep -q "libgmp.so" || die "$_b is not dynamically linked against libgmp.so."
		if ldd "$_b" | grep -qi "not found"; then
			ldd "$_b" >&2
			die "$_b has unresolved shared libraries."
		fi
	done

	log "Stripping binaries"
	strip "$_charon" "$_swanctl"

	log "Installing minimal runtime files into src/package/strongswan/"
	rm -rf "$SS_DIR"
	mkdir -p "$SS_DIR/libexec/ipsec" "$SS_DIR/sbin" "$SS_DIR/strongswan.d/charon"
	cp -p "$_charon" "$SS_CHARON"
	cp -p "$_swanctl" "$SS_SWANCTL"
	cp -p "$_confdir"/*.conf "$SS_CONFDIR/"

	# keep the bundled strongSwan license notice in sync with the built version
	if [ -f "$_srcdir/LICENSE" ]; then
		mkdir -p "$ROOT/licenses"
		cp -p "$_srcdir/LICENSE" "$ROOT/licenses/strongswan-LICENSE.txt"
	fi

	have_prebuilt || die "Post-build check failed: strongSwan files missing under src/package/strongswan/"
}

# decide how to obtain strongSwan for the .spk
ensure_strongswan() {
	if $REBUILD_SS; then
		build_strongswan
		return
	fi
	if have_prebuilt; then
		log "Prebuilt strongSwan found under src/package/strongswan/ - skipping source build"
		return
	fi
	build_strongswan
}

# ---------------------------------------------------------- stage 2: .spk
build_spk() {
	require_tool tar
	require_tool sed
	require_tool gzip
	require_tool md5sum

	PKG=$(sed -n 's/^package="\(.*\)"/\1/p' "$SRC/INFO")
	VER=$(sed -n 's/^version="\(.*\)"/\1/p' "$SRC/INFO")
	[ -n "$PKG" ] && [ -n "$VER" ] || die "package/version not found in src/INFO"

	log "Staging $PKG $VER"
	rm -rf "$ROOT/build/stage"
	mkdir -p "$STAGE" "$DIST"
	cp -r "$SRC/." "$STAGE/"

	# Bundle the license / third-party notices into the package so they ship
	# inside the .spk (GPLv2 requires the license to accompany the binaries).
	# They land under /var/packages/IKEv2VPN/target/ on the installed system.
	cp "$ROOT/LICENSE" "$STAGE/package/LICENSE"
	cp "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/package/THIRD_PARTY_NOTICES.md"
	mkdir -p "$STAGE/package/licenses"
	cp "$ROOT"/licenses/*.txt "$STAGE/package/licenses/" 2>/dev/null || true

	# Normalize CRLF -> LF for text files (safe on Windows checkouts). Exclude
	# PNGs and EVERY bundled strongSwan binary: running 's/\r$//' on an ELF
	# silently strips any byte ending in 0x0D and corrupts it. Excluding by
	# directory (libexec/ipsec + sbin) covers charon/xfrmi/_updown/swanctl and
	# any future binary without having to name each one.
	find "$STAGE" -type f ! -iname '*.png' \
		! -path '*/strongswan/libexec/ipsec/*' \
		! -path '*/strongswan/sbin/*' \
		-exec sed -i 's/\r$//' {} +

	# Conventional permissions: dirs 755, data files 644, executables 755.
	find "$STAGE/package" -type d -exec chmod 755 {} +
	find "$STAGE/package" -type f -exec chmod 644 {} +
	chmod 755 "$STAGE/package/bin/"* "$STAGE/package/ui/"*.cgi
	find "$STAGE/package/strongswan/libexec/ipsec" -type f -exec chmod 755 {} + 2>/dev/null || true
	find "$STAGE/package/strongswan/sbin" -type f -exec chmod 755 {} + 2>/dev/null || true

	log "Creating package.tgz"
	# On Windows/NTFS via Git Bash, chmod does not reliably stick on raw ELF
	# binaries (it works fine on shebang scripts). Force their executable bit
	# into the tar header directly instead: build package.tar in two passes -
	# everything except the strongSwan binary dirs first, then those dirs with
	# --mode=0755 appended.
	PKG_TAR="$STAGE/package.tar"
	tar -cf "$PKG_TAR" \
		--owner=0 --group=0 --numeric-owner \
		-C "$STAGE/package" \
		--exclude='./strongswan/libexec/ipsec' \
		--exclude='./strongswan/sbin' \
		.
	tar -rf "$PKG_TAR" \
		--owner=0 --group=0 --numeric-owner --mode=0755 \
		-C "$STAGE/package" \
		./strongswan/libexec/ipsec ./strongswan/sbin
	gzip -n -9 -c "$PKG_TAR" > "$STAGE/package.tgz"
	rm -f "$PKG_TAR"
	rm -rf "$STAGE/package"

	MD5=$(md5sum "$STAGE/package.tgz" | cut -d' ' -f1)
	sed -i "s/@CHECKSUM@/${MD5}/" "$STAGE/INFO"
	log "package.tgz md5: $MD5"

	chmod 644 "$STAGE/INFO" "$STAGE/PACKAGE_ICON.PNG" "$STAGE/PACKAGE_ICON_256.PNG" "$STAGE/package.tgz" \
		"$STAGE/conf/"* 2>/dev/null || true
	chmod 755 "$STAGE/scripts/"*

	SPK="$DIST/${PKG}-${VER}.spk"
	log "Creating $(basename "$SPK")"
	tar -cf "$SPK" \
		--owner=0 --group=0 --numeric-owner \
		-C "$STAGE" INFO PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG package.tgz scripts conf

	log "Done: $SPK"
	tar -tvf "$SPK"
}

# -------------------------------------------------------------------- main
ensure_strongswan
build_spk
