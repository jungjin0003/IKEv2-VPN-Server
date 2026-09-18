#!/bin/bash
#
# Unified build script for the IKEv2VPN Synology package (.spk).
#
# It performs three stages, in order:
#   1. (optional) Build the bundled static strongSwan from source and place
#      the minimal runtime files (charon, swanctl, strongswan.d/charon/*.conf)
#      into src/package/strongswan/.
#   2. (optional) Build the bundled ipset userspace tool from source and place
#      the single binary into src/package/ipset/.
#   3. Assemble the DSM .spk from src/ into dist/.
#
# Stages 1 and 2 are SKIPPED automatically when what they produce is already
# present under src/package/. Pass --rebuild-strongswan or --rebuild-ipset to
# force a fresh build from source.
#
# strongSwan is built --disable-shared --enable-static --enable-monolithic
# (no plugin .so files - everything baked into charon/swanctl) and links
# libgmp dynamically against the build machine's system libgmp.
#
# ipset needs libmnl, which DSM does not carry either. libmnl is built static
# into a private prefix and linked in, and ipset's own libipset is static as
# well, so the result is one executable with nothing to install beside it.
# The kernel side (ip_set, ip_set_hash_ip, xt_set) is already on DSM, so the
# kernel modules are not built. DSM 7.2.2 carries glibc 2.36 and the DSM
# kernel reports "ip_set: protocol 6", which is what the 6.x series speaks.
#
# Usage:
#   ./build.sh                       # build what is missing, then the .spk
#   ./build.sh --spk-only            # only assemble the .spk; never compile
#                                    #   (requires prebuilt strongSwan and
#                                    #    ipset; the mode build.ps1 uses on
#                                    #    Windows)
#   ./build.sh --rebuild-strongswan  # force a fresh strongSwan build from source
#   ./build.sh --rebuild-ipset       # force a fresh ipset build from source
#   ./build.sh --strongswan-version 6.0.7   # pin the strongSwan source version
#   ./build.sh --ipset-version 7.22         # pin the ipset source version
#   ./build.sh clean                 # remove everything downloaded and built
#   ./build.sh --clean               # same as clean
#   ./build.sh --clean-strongswan    # remove only the strongSwan artifacts
#   ./build.sh --clean-ipset         # remove only the ipset artifacts
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------- arguments
SS_VERSION="latest"
IPSET_VERSION="6.38"
SPK_ONLY=false
REBUILD_SS=false
REBUILD_IPSET=false
CLEAN_SS=false
CLEAN_IPSET=false
while [ $# -gt 0 ]; do
	case "$1" in
	--strongswan-version) SS_VERSION="$2"; shift 2 ;;
	--strongswan-version=*) SS_VERSION="${1#*=}"; shift ;;
	--ipset-version) IPSET_VERSION="$2"; shift 2 ;;
	--ipset-version=*) IPSET_VERSION="${1#*=}"; shift ;;
	--spk-only) SPK_ONLY=true; shift ;;
	--rebuild-strongswan) REBUILD_SS=true; shift ;;
	--rebuild-ipset) REBUILD_IPSET=true; shift ;;
	clean | --clean) CLEAN_SS=true; CLEAN_IPSET=true; shift ;;
	--clean-strongswan) CLEAN_SS=true; shift ;;
	--clean-ipset) CLEAN_IPSET=true; shift ;;
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
SS_PREFIX=/var/packages/IKEv2VPN/target/strongswan
SS_SYSCONFDIR=/var/packages/IKEv2VPN/etc
SS_SWANCTLDIR=/var/packages/IKEv2VPN/etc/swanctl
SS_PIDDIR=/var/packages/IKEv2VPN/var
SS_STAGE="$ROOT/build/strongswan-stage"          # DESTDIR for 'make install'

IPSET_DIR="$SRC/package/ipset"                   # bundled ipset (SPK source of truth)
IPSET_BIN="$IPSET_DIR/ipset"
# libmnl is a build-time dependency of ipset and ships inside the binary, so
# its version is not something a caller picks per build.
LIBMNL_VERSION="1.0.5"
MNL_PREFIX="$ROOT/build/libmnl-install"          # private prefix for the static libmnl
IPSET_STAGE="$ROOT/build/ipset-stage"            # DESTDIR for 'make install'

# ------------------------------------------------------------------ helpers
log()  { printf '\n\033[1;32m[*] %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$1" >&2; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$1" >&2; exit 1; }

require_tool() { command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1"; }

# true when the minimal runtime files are already present under src/
have_strongswan() {
	[ -f "$SS_CHARON" ] && [ -f "$SS_SWANCTL" ] && ls "$SS_CONFDIR"/*.conf >/dev/null 2>&1
}
# true when the bundled ipset binary is already present under src/
have_ipset() {
	[ -f "$IPSET_BIN" ]
}
# remove only artifacts created while obtaining/building bundled strongSwan
clean_strongswan() {
	log "Removing downloaded and built strongSwan artifacts"
	rm -rf "$SS_DIR" "$SS_STAGE" "$ROOT/build/strongswan-src.tar.bz2"
	if [ -d "$ROOT/build" ]; then
		find "$ROOT/build" -mindepth 1 -maxdepth 1 -type d -name 'strongswan-*' -exec rm -rf {} +
	fi
}
# remove only artifacts created while obtaining/building bundled ipset
clean_ipset() {
	log "Removing downloaded and built ipset artifacts"
	rm -rf "$IPSET_DIR" "$IPSET_STAGE" "$MNL_PREFIX" \
		"$ROOT/build/ipset-src.tar.bz2" "$ROOT/build/libmnl-src.tar.bz2"
	if [ -d "$ROOT/build" ]; then
		find "$ROOT/build" -mindepth 1 -maxdepth 1 -type d \
			\( -name 'ipset-*' -o -name 'libmnl-*' \) -exec rm -rf {} +
	fi
}
# --------------------------------------------------- stage 1: strongSwan
build_strongswan() {
	$SPK_ONLY && die "No prebuilt strongSwan available and --spk-only was given. Build strongSwan first on Linux with: ./build.sh"

	require_tool gcc
	require_tool make
	require_tool curl
	require_tool tar
	require_tool strip
	# --enable-monolithic resolves the plugin constructors through a Python
	# script, so configure fails without it rather than falling back.
	require_tool python3
	if [ ! -f /usr/include/gmp.h ] && [ ! -f /usr/include/x86_64-linux-gnu/gmp.h ]; then
		die "libgmp-dev (gmp.h) not found. Install it, e.g. 'sudo apt-get install libgmp-dev'."
	fi

	if [ "$SS_VERSION" = "latest" ]; then
		_srctar="strongswan.tar.bz2"
	else
		_srctar="strongswan-${SS_VERSION}.tar.bz2"
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
			--prefix="$SS_PREFIX" \
			--sysconfdir="$SS_SYSCONFDIR" \
			--with-swanctldir="$SS_SWANCTLDIR" \
			--with-piddir="$SS_PIDDIR" \
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

	_charon="$SS_STAGE$SS_PREFIX/libexec/ipsec/charon"
	_swanctl="$SS_STAGE$SS_PREFIX/sbin/swanctl"
	_confdir="$SS_STAGE$SS_SYSCONFDIR/strongswan.d/charon"

	log "Verifying build (monolithic, libgmp linkage)"
	if find "$SS_STAGE$SS_PREFIX" -name '*.so*' | grep -q .; then
		find "$SS_STAGE$SS_PREFIX" -name '*.so*' >&2
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

	have_strongswan || die "Post-build check failed: strongSwan files missing under src/package/strongswan/"
}

# decide how to obtain strongSwan for the .spk
ensure_strongswan() {
	if $REBUILD_SS; then
		build_strongswan
		return
	fi
	if have_strongswan; then
		log "Prebuilt strongSwan found under src/package/strongswan/ - skipping source build"
		return
	fi
	build_strongswan
}

# -------------------------------------------------------- stage 2: ipset
build_ipset() {
	$SPK_ONLY && die "No prebuilt ipset available and --spk-only was given. Build ipset first on Linux with: ./build.sh"

	require_tool gcc
	require_tool make
	require_tool curl
	require_tool tar
	require_tool strip
	require_tool pkg-config

	mkdir -p "$ROOT/build"

	# --- libmnl, static into a private prefix -------------------------------
	_mnlurl="https://www.netfilter.org/projects/libmnl/files/libmnl-${LIBMNL_VERSION}.tar.bz2"
	_mnldl="$ROOT/build/libmnl-src.tar.bz2"
	log "Downloading libmnl source ($_mnlurl)"
	curl -fL --retry 3 -o "$_mnldl" "$_mnlurl"

	# Same reason as the strongSwan listing above: `tar tjf | head -n1` kills
	# tar with SIGPIPE under `set -o pipefail`.
	_listing="$(tar tjf "$_mnldl")"
	_first="${_listing%%$'\n'*}"
	_mnldir="${_first%%/*}"
	_mnlsrc="$ROOT/build/$_mnldir"

	log "Extracting libmnl ($_mnldir)"
	rm -rf "$_mnlsrc"
	tar xjf "$_mnldl" -C "$ROOT/build"
	rm -f "$_mnldl"

	IPSET_CFLAGS="${CFLAGS:-} -march=x86-64 -O2"
	# Static only. Nothing shared is produced, so the ipset link below has no
	# libmnl.so to prefer even when the build machine has one installed.
	log "Configuring libmnl (static only, prefix $MNL_PREFIX)"
	rm -rf "$MNL_PREFIX"
	(
		cd "$_mnlsrc"
		CFLAGS="$IPSET_CFLAGS" ./configure \
			--prefix="$MNL_PREFIX" \
			--enable-static --disable-shared

		log "Compiling libmnl"
		make -j1

		log "Installing libmnl into $MNL_PREFIX"
		make install -j1
	)

	[ -f "$MNL_PREFIX/lib/libmnl.a" ] || die "libmnl.a was not produced under $MNL_PREFIX/lib"
	if ls "$MNL_PREFIX"/lib/libmnl.so* >/dev/null 2>&1; then
		die "libmnl built a shared library despite --disable-shared."
	fi
	[ -f "$MNL_PREFIX/lib/pkgconfig/libmnl.pc" ] || die "libmnl.pc is missing; ipset's configure will not find libmnl."

	# --- ipset --------------------------------------------------------------
	_ipseturl="https://ipset.netfilter.org/ipset-${IPSET_VERSION}.tar.bz2"
	_ipsetdl="$ROOT/build/ipset-src.tar.bz2"
	log "Downloading ipset source ($_ipseturl)"
	curl -fL --retry 3 -o "$_ipsetdl" "$_ipseturl"

	_listing="$(tar tjf "$_ipsetdl")"
	_first="${_listing%%$'\n'*}"
	_ipsetdir="${_first%%/*}"
	_ipsetsrc="$ROOT/build/$_ipsetdir"

	log "Extracting ipset ($_ipsetdir)"
	rm -rf "$_ipsetsrc"
	tar xjf "$_ipsetdl" -C "$ROOT/build"
	rm -f "$_ipsetdl"

	# --with-kmod=no: the kernel side is already on DSM, and modules built here
	#   would not match the DSM kernel anyway.
	# --disable-shared: libipset is linked into the binary instead of shipping
	#   beside it, the same reason libmnl is static.
	# PKG_CONFIG_PATH puts our own libmnl first so its .a is what gets linked.
	#   --prefix only decides where 'make install' writes; ipset does not read
	#   it back at run time, so the value is not a DSM path.
	log "Configuring ipset (kernel modules off, libmnl and libipset static)"
	rm -rf "$IPSET_STAGE"
	(
		cd "$_ipsetsrc"
		export PKG_CONFIG_PATH="$MNL_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
		CFLAGS="$IPSET_CFLAGS" \
		LDFLAGS="${LDFLAGS:-} -L$MNL_PREFIX/lib" \
		./configure \
			--prefix=/usr \
			--with-kmod=no \
			--enable-static --disable-shared

		log "Compiling ipset"
		make -j1

		log "Installing to staging (DESTDIR=$IPSET_STAGE)"
		mkdir -p "$IPSET_STAGE"
		make install -j1 DESTDIR="$IPSET_STAGE"
	)

	_ipset="$(find "$IPSET_STAGE" -type f -name ipset -perm -u+x | head -n1)"
	[ -n "$_ipset" ] || die "No ipset binary found under $IPSET_STAGE"

	log "Verifying build (single executable, no libmnl or libipset beside it)"
	if find "$IPSET_STAGE" -name 'libipset.so*' | grep -q .; then
		find "$IPSET_STAGE" -name 'libipset.so*' >&2
		die "ipset built libipset as a shared library rather than linking it in."
	fi
	file "$_ipset"
	if ldd "$_ipset" | grep -qE "libmnl|libipset"; then
		ldd "$_ipset" >&2
		die "$_ipset still depends on libmnl or libipset at run time."
	fi
	if ldd "$_ipset" | grep -qi "not found"; then
		ldd "$_ipset" >&2
		die "$_ipset has unresolved shared libraries."
	fi

	log "Stripping binary"
	strip "$_ipset"

	log "Installing the ipset binary into src/package/ipset/"
	rm -rf "$IPSET_DIR"
	mkdir -p "$IPSET_DIR"
	cp -p "$_ipset" "$IPSET_BIN"

	# keep the bundled licence notices in sync with the built versions
	mkdir -p "$ROOT/licenses"
	if [ -f "$_ipsetsrc/COPYING" ]; then
		cp -p "$_ipsetsrc/COPYING" "$ROOT/licenses/ipset-LICENSE.txt"
	fi
	if [ -f "$_mnlsrc/COPYING" ]; then
		cp -p "$_mnlsrc/COPYING" "$ROOT/licenses/libmnl-LICENSE.txt"
	fi

	have_ipset || die "Post-build check failed: ipset binary missing under src/package/ipset/"
}

# decide how to obtain ipset for the .spk
ensure_ipset() {
	if $REBUILD_IPSET; then
		build_ipset
		return
	fi
	if have_ipset; then
		log "Prebuilt ipset found under src/package/ipset/ - skipping source build"
		return
	fi
	build_ipset
}

# ---------------------------------------------------------- stage 3: .spk
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
	# PNGs and EVERY bundled binary: running 's/\r$//' on an ELF silently
	# strips any byte ending in 0x0D and corrupts it. Excluding by directory
	# (libexec/ipsec + sbin + ipset) covers charon/xfrmi/_updown/swanctl/ipset
	# and any future binary without having to name each one.
	find "$STAGE" -type f ! -iname '*.png' \
		! -path '*/strongswan/libexec/ipsec/*' \
		! -path '*/strongswan/sbin/*' \
		! -path '*/package/ipset/*' \
		-exec sed -i 's/\r$//' {} +

	# Conventional permissions: dirs 755, data files 644, executables 755.
	find "$STAGE/package" -type d -exec chmod 755 {} +
	find "$STAGE/package" -type f -exec chmod 644 {} +
	chmod 755 "$STAGE/package/bin/"* "$STAGE/package/ui/"*.cgi
	find "$STAGE/package/strongswan/libexec/ipsec" -type f -exec chmod 755 {} + 2>/dev/null || true
	find "$STAGE/package/strongswan/sbin" -type f -exec chmod 755 {} + 2>/dev/null || true
	find "$STAGE/package/ipset" -type f -exec chmod 755 {} + 2>/dev/null || true

	log "Creating package.tgz"
	# On Windows/NTFS via Git Bash, chmod does not reliably stick on raw ELF
	# binaries (it works fine on shebang scripts). Force their executable bit
	# into the tar header directly instead: build package.tar in two passes -
	# everything except the binary dirs first, then those dirs with
	# --mode=0755 appended.
	PKG_TAR="$STAGE/package.tar"
	tar -cf "$PKG_TAR" \
		--owner=0 --group=0 --numeric-owner \
		-C "$STAGE/package" \
		--exclude='./strongswan/libexec/ipsec' \
		--exclude='./strongswan/sbin' \
		--exclude='./ipset' \
		.
	tar -rf "$PKG_TAR" \
		--owner=0 --group=0 --numeric-owner --mode=0755 \
		-C "$STAGE/package" \
		./strongswan/libexec/ipsec ./strongswan/sbin ./ipset
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
if $CLEAN_SS || $CLEAN_IPSET; then
	if $CLEAN_SS; then clean_strongswan; fi
	if $CLEAN_IPSET; then clean_ipset; fi
	exit 0
fi

ensure_strongswan
ensure_ipset
build_spk
