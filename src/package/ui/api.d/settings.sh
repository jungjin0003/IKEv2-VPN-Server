# settings.sh - reading, validating and writing ${ETC}/settings.conf.

SETTINGS="${ETC}/settings.conf"

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
