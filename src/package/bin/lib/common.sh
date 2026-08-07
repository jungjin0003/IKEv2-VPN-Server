# common.sh - shared paths, logging and ownership helpers.
#
# Sourced by bin/ikev2ctl before every other module. Every filesystem
# location the modules use is defined here, so no module ever has to derive
# a path from another module's variable at source time - which keeps the
# modules order-independent and safe to auto-load by glob.

PKG="IKEv2VPN"
PKG_DIR="/var/packages/${PKG}"
TARGET="${PKG_DIR}/target"
ETC="${PKG_DIR}/etc"
VAR="${PKG_DIR}/var"
LOG="${VAR}/ikev2.log"

# VPN permission allowlist for DSM-account mode: one DSM login name per line.
# The Privileges page writes this. Only accounts listed here register for
# IKEv2/EAP-MSCHAPv2. If the file is absent, every active DSM account is allowed
# (legacy behaviour), so an upgrade keeps working until the page is applied.
VPNUSERS="${ETC}/vpnusers.conf"

CERT_DIR="${ETC}/cert"
CLIENTCA_DIR="${ETC}/clientca"
ISSUED_DIR="${CLIENTCA_DIR}/issued"

STRONGSWAN_DIR="${TARGET}/strongswan"
CHARON_BIN="${STRONGSWAN_DIR}/libexec/ipsec/charon"
SWANCTL_BIN="${STRONGSWAN_DIR}/sbin/swanctl"
STRONGSWAN_D="${STRONGSWAN_DIR}/strongswan.d"

STRONGSWAN_CONF_OUT="${ETC}/strongswan.conf"
SWANCTL_ETC="${ETC}/swanctl"
SWANCTL_CONF_OUT="${SWANCTL_ETC}/swanctl.conf"
CHARON_LOG="${VAR}/charon.log"
CHARON_PID="${VAR}/charon.pid"
CHARON_VICI="${VAR}/charon.vici"

SYNO_CERT_DIR="/usr/syno/etc/certificate/system/default"
SYNO_CERT_ARCHIVE="/usr/syno/etc/certificate/_archive"
# must match conf/privilege "username" - DSM's package user for this pkg
PKG_USER_DEFAULT="sc-ikev2vpn"

log() {
    mkdir -p "$VAR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

fail() {
    log "ERROR: $*"
    echo "ERROR: $*" >&2
    exit 1
}

# give package-user ownership to files the unprivileged side must read or
# preserve across upgrades (we usually run as root via sudo)
own_pkg() {
    [ "$(id -u)" = "0" ] || return 0
    O=$(stat -c '%U' "$TARGET" 2>/dev/null)
    [ -n "$O" ] && [ "$O" != "root" ] || O="$PKG_USER_DEFAULT"
    chown -R "$O" "$@" 2>/dev/null
}
