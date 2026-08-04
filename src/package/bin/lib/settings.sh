# settings.sh - package settings loading.
#
# Depends only on ${ETC} being set by the caller, so the scripts that are not
# built from the lib/ modules can source this file on its own and read
# settings exactly the same way ikev2ctl does.

SETTINGS="${ETC}/settings.conf"

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

    [ -f "$SETTINGS" ] && . "$SETTINGS"
}
