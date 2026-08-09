# settings.sh - package settings loading.
#
# Depends only on ${ETC} being set by the caller, so the scripts that are not
# built from the lib/ modules (bin/ikev2watch, bin/genprofile) can source this
# file on its own and read settings exactly the same way ikev2ctl does.
#
# Values come from three places, later ones winning:
#   1. the built-in defaults below
#   2. ${ETC}/settings.conf   - the settings the management UI writes
#   3. ${ETC}/settings.d/*.conf - drop-ins, one file per feature
# The drop-in directory means a feature can keep its own settings in its own
# file instead of having every setting share one file.

SETTINGS="${ETC}/settings.conf"
SETTINGS_D="${ETC}/settings.d"

# Every key a settings file may set. A file is data, so anything else in one is
# ignored rather than obeyed; a new setting is added here and given its default
# in load_settings below.
# One line: the lookup below tests for a key surrounded by spaces, so a key at
# the end of a line would be followed by a newline and never match.
SETTINGS_KEYS="IKEV2_HOSTNAME IKEV2_ENC IKEV2_AUTOBLOCK IKEV2_IFACE \
IKEV2_ENABLE_MSCHAPV2 IKEV2_SUBNET_MSCHAPV2 IKEV2_DNS_MSCHAPV2 IKEV2_CERT_MSCHAPV2 \
IKEV2_ENABLE_PSK IKEV2_PSK IKEV2_SUBNET_PSK IKEV2_DNS_PSK \
IKEV2_ENABLE_RSA IKEV2_SUBNET_RSA IKEV2_DNS_RSA IKEV2_CERT_RSA \
IKEV2_ENABLE_EAPTLS IKEV2_SUBNET_EAPTLS IKEV2_DNS_EAPTLS IKEV2_CERT_EAPTLS"

# Read one KEY="value" file into the IKEV2_* variables.
#
# The file is parsed, not sourced. Sourcing would make every value in it shell
# input, so a value carrying a backtick or $( ) would run - and load_settings
# runs inside ikev2ctl, which runs as root. Nothing here expands a value: the
# key is matched against SETTINGS_KEYS first, so what eval receives is one of
# those literal names, and the value reaches it as \$_val, which an assignment
# takes whole without splitting, globbing or re-reading it.
read_settings_file() {
    [ -f "$1" ] || return 0
    _cr=$(printf '\r')
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line=${_line%"$_cr"}
        _line=${_line#"${_line%%[! 	]*}"}
        case "$_line" in
            "" | \#*) continue ;;
        esac

        _key=${_line%%=*}
        [ "$_key" != "$_line" ] || continue
        _val=${_line#*=}
        case "$_val" in
            \"*\") _val=${_val#\"}; _val=${_val%\"} ;;
        esac

        case " $SETTINGS_KEYS " in
            *" $_key "*) eval "$_key=\$_val" ;;
        esac
    done < "$1"
    return 0
}

load_settings() {
    # defaults - each auth method gets its own client IP pool/DNS so the 4
    # conns can be routed/firewalled independently
    IKEV2_HOSTNAME=""
    IKEV2_ENC="auto"              # auto | aes256 | aes128
    IKEV2_AUTOBLOCK="no"
    IKEV2_IFACE=""                # "" = listen on all interfaces; else iface name

    # IKEV2_CERT_* = chosen DSM certificate archive id ("" = system default);
    # the server presents that certificate to clients
    IKEV2_ENABLE_MSCHAPV2="no"    # EAP-MSCHAPv2, DSM accounts only (Privileges allowlist)
    IKEV2_SUBNET_MSCHAPV2="10.10.0.0/24"
    IKEV2_DNS_MSCHAPV2="8.8.8.8"
    IKEV2_CERT_MSCHAPV2=""

    IKEV2_ENABLE_PSK="no"
    IKEV2_PSK=""
    IKEV2_SUBNET_PSK="10.11.0.0/24"
    IKEV2_DNS_PSK="8.8.8.8"

    IKEV2_ENABLE_RSA="no"
    IKEV2_SUBNET_RSA="10.12.0.0/24"
    IKEV2_DNS_RSA="8.8.8.8"
    IKEV2_CERT_RSA=""

    IKEV2_ENABLE_EAPTLS="no"
    IKEV2_SUBNET_EAPTLS="10.13.0.0/24"
    IKEV2_DNS_EAPTLS="8.8.8.8"
    IKEV2_CERT_EAPTLS=""

    read_settings_file "$SETTINGS"

    # per-feature drop-ins, read in glob order
    for _sf in "${SETTINGS_D}"/*.conf; do
        read_settings_file "$_sf"
    done

    return 0
}
