# users.sh - the Privileges page: DSM accounts and the VPN allowlist.

# DSM VPN permission allowlist (one DSM login name per line); written by the
# Privileges page. ikev2ctl registers only these DSM accounts.
VPNUSERS="${ETC}/vpnusers.conf"

# Privileges page: the DSM local accounts with VPN status + allow flag
# ([{name,status,allowed}]). status: normal|disabled ; allowed: yes|no
do_dsmusers() {
    json_headers
    printf '['
    FIRST=1
    "$AS" ikev2ctl dsm-users 2>/dev/null | while IFS='|' read -r NM ST AL; do
        [ -n "$NM" ] || continue
        [ $FIRST -eq 1 ] || printf ','
        printf '{"name":"%s","status":"%s","allowed":"%s"}' \
            "$(json_str "$NM")" "$(json_str "$ST")" "$(json_str "$AL")"
        FIRST=0
    done
    printf ']'
}

# Privileges page apply: persist the allowlist (comma-separated DSM login names),
# then stop the service and restart it so only the permitted DSM accounts are
# registered (stop -> re-register -> restart, per requirement).
do_vpnperm() {
    require_post
    LIST=$(param users)
    mkdir -p "$ETC"
    : > "${VPNUSERS}.tmp"
    OIFS=$IFS; IFS=','
    for U in $LIST; do
        IFS=$OIFS
        [ -n "$U" ] || { IFS=','; continue; }
        printf '%s' "$U" | grep -Eq '^[A-Za-z0-9._-]{1,32}$' \
            || { rm -f "${VPNUSERS}.tmp"; json_err "invalid username in list"; }
        echo "$U" >> "${VPNUSERS}.tmp"
        IFS=','
    done
    IFS=$OIFS
    mv "${VPNUSERS}.tmp" "$VPNUSERS"
    chmod 600 "$VPNUSERS"

    # stop the running service, then re-apply so charon reloads with exactly
    # the permitted DSM accounts registered.
    if [ -f "${ETC}/enabled" ]; then
        "$AS" ikev2ctl remove >/dev/null 2>&1
        OUT=$("$AS" ikev2ctl apply 2>&1) || json_err "$(printf '%s' "$OUT" | tail -n 1 | sed 's/"/\\"/g')"
    fi
    json_ok
}
