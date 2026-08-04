# log.sh - the Log page: connection events and the raw log export.

do_events() {
    json_headers
    printf '['
    FIRST=1
    "$AS" ikev2watch events 300 2>/dev/null | while IFS='|' read -r T PROTO USER EVENT IP; do
        [ -n "$T" ] || continue
        [ $FIRST -eq 1 ] || printf ','
        printf '{"time":"%s","proto":"%s","user":"%s","event":"%s","ip":"%s"}' \
            "$(json_str "$T")" "$(json_str "$PROTO")" "$(json_str "$USER")" \
            "$(json_str "$EVENT")" "$(json_str "$IP")"
        FIRST=0
    done
    printf ']'
}

do_events_clear() {
    require_post
    "$AS" ikev2watch events-clear >/dev/null 2>&1
    json_ok
}

do_export_log() {
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Content-Disposition: attachment; filename="ikev2-log.txt"\r\n\r\n'
    "$AS" ikev2ctl log-dump 2>/dev/null
}
