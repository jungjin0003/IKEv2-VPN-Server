#!/bin/sh
# api.cgi - IKEv2 VPN Server management API (behind DSM login).
# Runs as the package user on DSM 7; privileged operations go through
# bin/asroot (sudo rule installed once by 'ikev2-setup install').
#
# This file only holds what every handler needs - request parsing, the JSON
# helpers and the privileged-call wrappers. The handlers themselves live in
# api.d/, one file per area; they are loaded before the dispatch below.

PKG="IKEv2VPN"
PKG_DIR="/var/packages/${PKG}"
TARGET="${PKG_DIR}/target"
ETC="${PKG_DIR}/etc"
AS="${TARGET}/bin/asroot"
CTL="${TARGET}/bin/ikev2ctl"
API_D="${TARGET}/ui/api.d"

# root | sudo | none - how privileged calls will be executed
priv_state() {
    if [ "$(id -u)" = "0" ]; then
        echo "root"
    elif command -v sudo >/dev/null 2>&1 && sudo -n -l "$CTL" >/dev/null 2>&1; then
        echo "sudo"
    else
        echo "none"
    fi
}

# ------------------------------------------------------------- http helpers

json_headers() {
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
}

json_err() {
    json_headers
    printf '{"success":false,"error":"%s"}' "$1"
    exit 0
}

json_ok() {
    json_headers
    printf '{"success":true}'
    exit 0
}

json_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

urldecode() {
    printf '%b' "$(printf '%s' "$1" | sed -e 's/+/ /g' -e 's/%\(..\)/\\x\1/g')"
}

# param NAME <- $DATA (urlencoded)
param() {
    _v=$(printf '%s' "$DATA" | tr '&' '\n' | sed -n "s/^$1=//p" | head -n 1)
    urldecode "$_v"
}

# ---------------------------------------------------------------- read input

QS="${QUERY_STRING:-}"
BODY=""
if [ "${REQUEST_METHOD:-GET}" = "POST" ] && [ -n "${CONTENT_LENGTH:-}" ]; then
    BODY=$(head -c "$CONTENT_LENGTH" 2>/dev/null)
fi
DATA="${QS}&${BODY}"

ACTION=$(param action)

require_post() {
    [ "${REQUEST_METHOD:-GET}" = "POST" ] || json_err "POST required"
}

reapply_if_enabled() {
    if [ -f "${ETC}/enabled" ]; then
        "$AS" ikev2ctl apply >/dev/null 2>&1
    fi
}

# ------------------------------------------------------------------ dispatch

for _h in "${API_D}"/*.sh; do
    [ -f "$_h" ] && . "$_h"
done

case "$ACTION" in
    status)       do_status ;;
    enable)       do_enable ;;
    disable)      do_disable ;;
    restart)      do_restart ;;
    save)         do_save ;;
    dsmusers)     do_dsmusers ;;
    dsmcerts)     do_dsmcerts ;;
    vpnperm)      do_vpnperm ;;
    certissue)    do_certissue ;;
    certdel)      do_certdel ;;
    profile)      do_profile ;;
    clients)      do_clients ;;
    connections)  do_connections ;;
    disconnect)   do_disconnect ;;
    events)       do_events ;;
    eventsclear)  do_events_clear ;;
    exportlog)    do_export_log ;;
    *)            json_err "unknown action" ;;
esac
