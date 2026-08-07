#!/bin/sh
# api.cgi - IKEv2 VPN Server management API.
# Runs as the package user on DSM 7; privileged operations go through
# bin/asroot (sudo rule installed once by 'ikev2-setup install').
#
# DSM does not gate what it serves from /webman/3rdparty/, so the DSM session
# is established here, by lib/auth.sh, before any handler is loaded. Nothing
# below the gate runs for a caller without one.
#
# This file only holds what every handler needs - request parsing, the JSON
# helpers and the privileged-call wrappers. The handlers themselves live in
# api.d/, one file per area, each defining do_<action> for the actions it
# serves; they are loaded and dispatched to by name at the bottom, so adding
# an action never means editing this file.

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

# ----------------------------------------------------------------- auth gate

# Nothing has been read from the client yet. The session is established from
# the query string alone, so an unauthenticated caller never gets a request
# body buffered on its behalf - the download path puts its token there for
# exactly this reason, a form being unable to set a header.
QS="${QUERY_STRING:-}"
DATA="$QS"

. "${TARGET}/lib/auth.sh"

if ! web_authenticate "$(param SynoToken)"; then
    printf 'Status: 403 Forbidden\r\n'
    json_headers
    printf '{"success":false,"error":"not authenticated"}'
    exit 0
fi

# ---------------------------------------------------------------- read input

BODY=""
if [ "${REQUEST_METHOD:-GET}" = "POST" ] && [ -n "${CONTENT_LENGTH:-}" ]; then
    # bound what is read into a shell variable; the largest legitimate request
    # is the privileges list and sits far below this
    case "$CONTENT_LENGTH" in
        "" | *[!0-9]*) CONTENT_LENGTH=0 ;;
    esac
    if [ "$CONTENT_LENGTH" -gt 65536 ]; then
        printf 'Status: 413 Payload Too Large\r\n'
        json_headers
        printf '{"success":false,"error":"request too large"}'
        exit 0
    fi
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

# The action names a handler function directly, so accept only a plain name
# and only run it when it resolved to one of the functions we just loaded:
# 'command -v' prints the bare name for a shell function but an absolute path
# for anything on $PATH, so a request can never reach an external command.
printf '%s' "$ACTION" | grep -Eq '^[a-z][a-z0-9_]*$' || json_err "unknown action"
[ "$(command -v "do_${ACTION}" 2>/dev/null)" = "do_${ACTION}" ] || json_err "unknown action"

"do_${ACTION}"
