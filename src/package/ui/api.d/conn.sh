# conn.sh - active client sessions: list and disconnect.

# proto label for a strongSwan/Openswan conn name
proto_label() {
    case "$1" in
        ikev2)        echo "MSCHAPv2" ;;
        ikev2-psk)    echo "PSK" ;;
        ikev2-rsa)    echo "RSA" ;;
        ikev2-eaptls) echo "EAP-TLS" ;;
        *)            echo "$1" ;;
    esac
}

do_clients() {
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    "$AS" ikev2ctl clients 2>/dev/null
}

do_connections() {
    json_headers
    printf '['
    FIRST=1
    "$AS" ikev2ctl clients 2>/dev/null | tail -n +2 | while IFS='|' read -r CONN IP VIP STATE; do
        [ -n "$CONN" ] || continue
        [ $FIRST -eq 1 ] || printf ','
        printf '{"proto":"%s","ip":"%s","virtual_ip":"%s","state":"%s","conn":"%s"}' \
            "$(json_str "$(proto_label "$CONN")")" "$(json_str "$IP")" "$(json_str "$VIP")" \
            "$(json_str "$STATE")" "$(json_str "$CONN")"
        FIRST=0
    done
    printf ']'
}

do_disconnect() {
    require_post
    CONN=$(param conn)
    case "$CONN" in
        ikev2|ikev2-psk|ikev2-rsa|ikev2-eaptls) ;;
        *) json_err "invalid connection" ;;
    esac
    "$AS" ikev2ctl disconnect "$CONN" >/dev/null 2>&1
    json_ok
}
