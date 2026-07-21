#!/bin/sh
# api.cgi - IKEv2 VPN Server management API (behind DSM login).
# Runs as the package user on DSM 7; privileged operations go through
# bin/asroot (sudo rule installed once by 'ikev2-setup install').

PKG="IKEv2VPN"
PKG_DIR="/var/packages/${PKG}"
TARGET="${PKG_DIR}/target"
ETC="${PKG_DIR}/etc"
AS="${TARGET}/bin/asroot"
CTL="${TARGET}/bin/ikev2ctl"
SETTINGS="${ETC}/settings.conf"
# DSM VPN permission allowlist (one DSM login name per line); written by the
# 권한(Privileges) page. ikev2ctl registers only these DSM accounts.
VPNUSERS="${ETC}/vpnusers.conf"

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

# ------------------------------------------------------------------- actions

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

valid_ip()   { printf '%s' "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; }
# client IP range is always a /24 with a .0 network part (CIDR fixed at 24)
valid_subnet24() { printf '%s' "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){2}\.0/24$'; }
# DSM certificate archive id (empty = system default)
valid_certid() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._-]{0,40}$'; }
# resolve the DNS setting from the manual/auto pair: manual requires a valid
# IP; auto stores an empty value (the daemon then pushes the NAS's own DNS)
resolve_dns() {
    if [ "$(param dns_manual)" = "yes" ]; then
        DNS=$(param dns); valid_ip "$DNS" || json_err "invalid DNS"
    else
        DNS=""
    fi
}

# load current settings.conf into IKEV2_* vars (all keys default-populated
# first so a save on one "scope" never clobbers the others' values)
load_current_settings() {
    IKEV2_HOSTNAME=""; IKEV2_ENC="auto"; IKEV2_AUTOBLOCK="no"; IKEV2_IFACE=""
    IKEV2_ENABLE_MSCHAPV2="no"
    IKEV2_SUBNET_MSCHAPV2="10.10.0.0/24"; IKEV2_DNS_MSCHAPV2="8.8.8.8"; IKEV2_CERT_MSCHAPV2=""
    IKEV2_ENABLE_PSK="no"; IKEV2_PSK=""
    IKEV2_SUBNET_PSK="10.11.0.0/24"; IKEV2_DNS_PSK="8.8.8.8"
    IKEV2_ENABLE_RSA="no"
    IKEV2_SUBNET_RSA="10.12.0.0/24"; IKEV2_DNS_RSA="8.8.8.8"; IKEV2_CERT_RSA=""
    IKEV2_ENABLE_EAPTLS="no"
    IKEV2_SUBNET_EAPTLS="10.13.0.0/24"; IKEV2_DNS_EAPTLS="8.8.8.8"; IKEV2_CERT_EAPTLS=""
    [ -f "$SETTINGS" ] && . "$SETTINGS"
}

write_settings() {
    mkdir -p "$ETC"
    {
        echo "IKEV2_HOSTNAME=\"${IKEV2_HOSTNAME}\""
        echo "IKEV2_ENC=\"${IKEV2_ENC}\""
        echo "IKEV2_AUTOBLOCK=\"${IKEV2_AUTOBLOCK}\""
        echo "IKEV2_IFACE=\"${IKEV2_IFACE}\""
        echo "IKEV2_ENABLE_MSCHAPV2=\"${IKEV2_ENABLE_MSCHAPV2}\""
        echo "IKEV2_SUBNET_MSCHAPV2=\"${IKEV2_SUBNET_MSCHAPV2}\""
        echo "IKEV2_DNS_MSCHAPV2=\"${IKEV2_DNS_MSCHAPV2}\""
        echo "IKEV2_CERT_MSCHAPV2=\"${IKEV2_CERT_MSCHAPV2}\""
        echo "IKEV2_ENABLE_PSK=\"${IKEV2_ENABLE_PSK}\""
        echo "IKEV2_PSK=\"${IKEV2_PSK}\""
        echo "IKEV2_SUBNET_PSK=\"${IKEV2_SUBNET_PSK}\""
        echo "IKEV2_DNS_PSK=\"${IKEV2_DNS_PSK}\""
        echo "IKEV2_ENABLE_RSA=\"${IKEV2_ENABLE_RSA}\""
        echo "IKEV2_SUBNET_RSA=\"${IKEV2_SUBNET_RSA}\""
        echo "IKEV2_DNS_RSA=\"${IKEV2_DNS_RSA}\""
        echo "IKEV2_CERT_RSA=\"${IKEV2_CERT_RSA}\""
        echo "IKEV2_ENABLE_EAPTLS=\"${IKEV2_ENABLE_EAPTLS}\""
        echo "IKEV2_SUBNET_EAPTLS=\"${IKEV2_SUBNET_EAPTLS}\""
        echo "IKEV2_DNS_EAPTLS=\"${IKEV2_DNS_EAPTLS}\""
        echo "IKEV2_CERT_EAPTLS=\"${IKEV2_CERT_EAPTLS}\""
    } > "$SETTINGS"
    chmod 600 "$SETTINGS"
}

# scope=general : hostname, enc, autoblock
# scope=mschapv2|psk|rsa|eaptls : that method's own fields only
do_save() {
    require_post
    SCOPE=$(param scope)
    load_current_settings

    case "$SCOPE" in
    general)
        HOSTNAME=$(param hostname)
        ENC=$(param enc); case "$ENC" in aes256|aes128) ;; *) ENC="auto" ;; esac
        AUTOBLOCK=$(param autoblock); [ "$AUTOBLOCK" = "yes" ] || AUTOBLOCK="no"
        if [ -n "$HOSTNAME" ]; then
            printf '%s' "$HOSTNAME" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$' \
                || json_err "invalid hostname"
        fi
        IFACE=$(param iface)
        if [ -n "$IFACE" ]; then
            printf '%s' "$IFACE" | grep -Eq '^[A-Za-z0-9._-]{1,15}$' || json_err "invalid interface"
            ip link show dev "$IFACE" >/dev/null 2>&1 || json_err "interface not found: $IFACE"
        fi
        IKEV2_HOSTNAME="$HOSTNAME"; IKEV2_ENC="$ENC"; IKEV2_AUTOBLOCK="$AUTOBLOCK"; IKEV2_IFACE="$IFACE"
        ;;
    mschapv2)
        EN=$(param enabled); [ "$EN" = "yes" ] || EN="no"
        SUBNET=$(param subnet); resolve_dns; CERT=$(param cert)
        valid_subnet24 "$SUBNET" || json_err "invalid IP range (expected x.x.x.0/24)"
        valid_certid "$CERT" || json_err "invalid certificate id"
        IKEV2_ENABLE_MSCHAPV2="$EN"
        IKEV2_SUBNET_MSCHAPV2="$SUBNET"; IKEV2_DNS_MSCHAPV2="$DNS"; IKEV2_CERT_MSCHAPV2="$CERT"
        ;;
    psk)
        EN=$(param enabled); [ "$EN" = "yes" ] || EN="no"
        SUBNET=$(param subnet); resolve_dns; PSK=$(param psk)
        valid_subnet24 "$SUBNET" || json_err "invalid IP range (expected x.x.x.0/24)"
        if [ "$EN" = "yes" ]; then
            [ -n "$PSK" ] || PSK=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)
            [ ${#PSK} -ge 8 ]  || json_err "PSK too short (min 8)"
            [ ${#PSK} -le 64 ] || json_err "PSK too long (max 64)"
            case "$PSK" in *\"*|*\\*|*\ *) json_err "PSK must not contain quote, backslash or space" ;; esac
        fi
        IKEV2_ENABLE_PSK="$EN"; IKEV2_PSK="$PSK"
        IKEV2_SUBNET_PSK="$SUBNET"; IKEV2_DNS_PSK="$DNS"
        ;;
    rsa)
        EN=$(param enabled); [ "$EN" = "yes" ] || EN="no"
        SUBNET=$(param subnet); resolve_dns; CERT=$(param cert)
        valid_subnet24 "$SUBNET" || json_err "invalid IP range (expected x.x.x.0/24)"
        valid_certid "$CERT" || json_err "invalid certificate id"
        IKEV2_ENABLE_RSA="$EN"; IKEV2_SUBNET_RSA="$SUBNET"; IKEV2_DNS_RSA="$DNS"; IKEV2_CERT_RSA="$CERT"
        ;;
    eaptls)
        EN=$(param enabled); [ "$EN" = "yes" ] || EN="no"
        SUBNET=$(param subnet); resolve_dns; CERT=$(param cert)
        valid_subnet24 "$SUBNET" || json_err "invalid IP range (expected x.x.x.0/24)"
        valid_certid "$CERT" || json_err "invalid certificate id"
        IKEV2_ENABLE_EAPTLS="$EN"; IKEV2_SUBNET_EAPTLS="$SUBNET"; IKEV2_DNS_EAPTLS="$DNS"; IKEV2_CERT_EAPTLS="$CERT"
        ;;
    *)
        json_err "unknown scope"
        ;;
    esac

    write_settings
    reapply_if_enabled
    json_ok
}

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

# 권한 page: the DSM local accounts with VPN status + allow flag
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

# 권한 page apply: persist the allowlist (comma-separated DSM login names),
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

do_profile() {
    TYPE=$(param type)
    U=$(param user)
    printf '%s' "$U" | grep -Eq '^[A-Za-z0-9._-]{0,32}$' || U=""

    case "$TYPE" in
        ios)
            printf 'Content-Type: application/x-apple-aspen-config\r\n'
            printf 'Content-Disposition: attachment; filename="ikev2-vpn.mobileconfig"\r\n\r\n'
            "$AS" genprofile ios "$U"
            ;;
        ios_psk)
            printf 'Content-Type: application/x-apple-aspen-config\r\n'
            printf 'Content-Disposition: attachment; filename="ikev2-vpn-psk.mobileconfig"\r\n\r\n'
            "$AS" genprofile ios-psk
            ;;
        windows)
            printf 'Content-Type: text/plain; charset=utf-8\r\n'
            printf 'Content-Disposition: attachment; filename="ikev2-vpn.ps1"\r\n\r\n'
            "$AS" genprofile windows
            ;;
        android)
            printf 'Content-Type: text/plain; charset=utf-8\r\n'
            printf 'Content-Disposition: attachment; filename="ikev2-android-guide.txt"\r\n\r\n'
            "$AS" genprofile android
            ;;
        ca)
            printf 'Content-Type: application/x-x509-ca-cert\r\n'
            printf 'Content-Disposition: attachment; filename="ikev2-ca.cer"\r\n\r\n'
            "$AS" genprofile ca
            ;;
        *)
            json_err "unknown profile type"
            ;;
    esac
}

do_clients() {
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    "$AS" ikev2ctl clients 2>/dev/null
}

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

json_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

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
