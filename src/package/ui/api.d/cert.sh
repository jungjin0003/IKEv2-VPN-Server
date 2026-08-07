# cert.sh - client certificate issue/delete, and the DSM certificate list.

do_certissue() {
    require_post
    U=$(param user)
    P=$(param p12pass)
    printf '%s' "$U" | grep -Eq '^[A-Za-z0-9._-]{1,32}$' \
        || json_err "invalid certificate name (allowed: A-Z a-z 0-9 . _ - , max 32)"
    [ -n "$P" ] || json_err "empty p12 password"
    case "$P" in
        *\"*|*\\*) json_err "password must not contain quote or backslash" ;;
    esac

    # create the temp file ourselves so it stays readable by this
    # (package) user after root writes the p12 into it via sudo
    TMP=$(mktemp /tmp/ikev2-p12.XXXXXX 2>/dev/null) || TMP="/tmp/ikev2-p12.$$"
    if ! "$AS" ikev2ctl cert-issue "$U" "$P" "$TMP" >/dev/null 2>&1; then
        rm -f "$TMP"
        json_err "certificate issue failed (see /var/packages/IKEv2VPN/var/ikev2.log)"
    fi
    printf 'Content-Type: application/x-pkcs12\r\n'
    printf 'Content-Disposition: attachment; filename="ikev2-%s.p12"\r\n\r\n' "$U"
    cat "$TMP"
    rm -f "$TMP"
}

do_certdel() {
    require_post
    U=$(param user)
    printf '%s' "$U" | grep -Eq '^[A-Za-z0-9._-]{1,32}$' || json_err "invalid certificate name"
    "$AS" ikev2ctl cert-del "$U" >/dev/null 2>&1
    json_ok
}

# DSM certificates available for a VPN server to present ([{id,label}])
do_dsmcerts() {
    json_headers
    printf '['
    FIRST=1
    "$AS" ikev2ctl dsm-certs 2>/dev/null | while IFS='|' read -r CID LBL; do
        [ -n "$CID" ] || continue
        [ $FIRST -eq 1 ] || printf ','
        printf '{"id":"%s","label":"%s"}' "$(json_str "$CID")" "$(json_str "$LBL")"
        FIRST=0
    done
    printf ']'
}
