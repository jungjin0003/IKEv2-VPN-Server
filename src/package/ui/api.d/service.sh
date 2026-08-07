# service.sh - service state: status, start, stop, restart.

do_status() {
    json_headers
    printf '{'
    printf '"success":true'
    printf ',"priv":"%s"' "$(priv_state)"
    printf ',"run_as":"%s"' "$(id -un 2>/dev/null)"
    printf ',"setup_cmd":"sudo %s/bin/ikev2-setup install"' "$TARGET"
    "$AS" ikev2ctl status 2>/dev/null | while IFS='=' read -r K V; do
        [ -n "$K" ] || continue
        V=$(printf '%s' "$V" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        printf ',"%s":"%s"' "$K" "$V"
    done
    # issued client certificates (name|expiry)
    printf ',"cert_list":['
    FIRST=1
    "$AS" ikev2ctl cert-list 2>/dev/null | while IFS='|' read -r N E; do
        [ -n "$N" ] || continue
        [ $FIRST -eq 1 ] || printf ','
        E=$(printf '%s' "$E" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        printf '{"name":"%s","expires":"%s"}' "$N" "$E"
        FIRST=0
    done
    printf ']}'
}

do_enable() {
    require_post
    OUT=$("$AS" ikev2ctl apply 2>&1) || json_err "$(printf '%s' "$OUT" | tail -n 1 | sed 's/"/\\"/g')"
    json_ok
}

do_disable() {
    require_post
    "$AS" ikev2ctl remove >/dev/null 2>&1
    rm -f "${ETC}/enabled" 2>/dev/null
    json_ok
}

do_restart() {
    require_post
    [ -f "${ETC}/enabled" ] || json_err "service is not running"
    OUT=$("$AS" ikev2ctl restart 2>&1) || json_err "$(printf '%s' "$OUT" | tail -n 1 | sed 's/"/\\"/g')"
    json_ok
}
