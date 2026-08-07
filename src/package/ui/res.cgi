#!/bin/sh
# res.cgi - the management page's static files, behind the DSM session check.
#
# app.css, js/ and vendor/ live in www/, outside the directory DSM symlinks
# into its web root, so nginx cannot hand them out on its own.
#
# They are addressed through the path that follows this script's name -
# res.cgi/js/main.js - rather than a query parameter. That matters: the ES
# modules import each other by relative path ("./store.js", "../preact.js"),
# and the browser resolves those against the URL the module was fetched from.
# With the file in the path they resolve to res.cgi/... again and come back
# through this check; with the file in a query string they would resolve to
# a bare .js next to the CGI, which does not exist. PATH_INFO is what carries
# that remainder.

PKG="IKEv2VPN"
TARGET="/var/packages/${PKG}/target"
ROOT="${TARGET}/www"

. "${TARGET}/lib/auth.sh"

deny() {
    printf 'Status: %s\r\n' "$1"
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    exit 0
}

web_authenticate || deny "403 Forbidden"

REL="${PATH_INFO:-}"
# Fallback for a server that does not pass PATH_INFO. The relative imports do
# not survive it, so this is only good enough to fetch a single named file -
# it is here to make that failure diagnosable rather than silent.
if [ -z "$REL" ]; then
    REL="/$(printf '%s' "${QUERY_STRING:-}" | tr '&' '\n' | sed -n 's/^f=//p' | head -n 1)"
fi

# One or more plain path segments and nothing else. The character check comes
# first and is a case glob rather than a grep: it sees the whole value at once,
# so an embedded newline cannot hide a second line from the line-oriented
# pattern that follows. Then no traversal, then the shape - leading slash, no
# empty segment, no trailing slash.
case "$REL" in
    *[!/A-Za-z0-9._-]*) deny "400 Bad Request" ;;
    *..*)               deny "400 Bad Request" ;;
esac
printf '%s' "$REL" | grep -Eq '^(/[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*)+$' \
    || deny "400 Bad Request"

# Serve the asset types the page actually loads, and nothing else.
# SVG is deliberately absent: it can carry script, and the page's icons are
# inline markup rather than files, so nothing needs it served.
case "$REL" in
    *.js)   CT="application/javascript; charset=utf-8" ;;
    *.css)  CT="text/css; charset=utf-8" ;;
    *.png)  CT="image/png" ;;
    *)      deny "403 Forbidden" ;;
esac

FILE="${ROOT}${REL}"
[ -f "$FILE" ] || deny "404 Not Found"

# The checks above already keep the request itself inside www/, so this is
# about the tree rather than the caller: a symlink planted under www/ would be
# followed, and nothing else states that everything served has to live there.
# Both sides are resolved because target/ is itself a symlink into @appstore -
# comparing an unresolved prefix would refuse every file. If the resolution is
# not available the request-shape checks still stand on their own, so serve.
RROOT=$(readlink -f "$ROOT" 2>/dev/null || true)
RFILE=$(readlink -f "$FILE" 2>/dev/null || true)
if [ -n "$RROOT" ] && [ -n "$RFILE" ]; then
    case "$RFILE" in
        "$RROOT"/*) ;;
        *) deny "403 Forbidden" ;;
    esac
fi

printf 'Content-Type: %s\r\n' "$CT"
printf 'Cache-Control: private, no-store\r\n'
printf 'X-Content-Type-Options: nosniff\r\n\r\n'
cat "$FILE"
