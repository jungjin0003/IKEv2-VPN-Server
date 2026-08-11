# actions.sh - the operations bin/ikev2ctl exposes on its command line.

# structured connection list: "conn|peer_ip|virtual_ip|state" per line,
# via 'swanctl --list-sas' (vici) - much more reliable than text-scraping
# the legacy 'ipsec status' output. Parses the documented human-readable
# format (conn name/#id/ESTABLISHED header line, indented "remote '<id>'
# @ <ip>[port]" line, indented child-SA "remote <cidr>" traffic-selector
# line) - not verified against a live established session.
list_connections() {
    charon_running || return 0
    swanctl --list-sas 2>/dev/null | awk '
    /^[A-Za-z0-9_-]+: #[0-9]+, ESTABLISHED/ {
        name = $1; sub(/:$/, "", name)
        active = 1; peer = "-"; vip = "-"
        next
    }
    active && /^  remote / {
        if (match($0, /@ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
            s = substr($0, RSTART, RLENGTH); sub(/^@ /, "", s); peer = s
        }
        next
    }
    active && /^    remote [0-9]/ {
        if (match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) vip = substr($0, RSTART, RLENGTH)
        print name "|" peer "|" vip "|established"
        active = 0
    }'
}

# terminate one connection by its swanctl conn name (ikev2, ikev2-psk,
# ikev2-rsa or ikev2-eaptls) - drops all active sessions on that conn
disconnect_conn() {
    NAME="$1"
    case "$NAME" in
        ikev2|ikev2-psk|ikev2-rsa|ikev2-eaptls) ;;
        *) fail "invalid connection name" ;;
    esac
    charon_running || fail "charon not running"
    swanctl --terminate --ike "$NAME" >/dev/null 2>&1
    log "disconnected all sessions on ${NAME}"
}

# full service restart: tear down the running charon, then re-apply from
# scratch (do_apply then takes the start_charon path since none is running)
do_restart() {
    [ -f "${ETC}/enabled" ] || fail "service is not enabled"
    stop_charon
    do_apply
    log "service restarted"
}

do_apply() {
    load_settings
    mkdir -p "$SWANCTL_ETC"

    # standalone charon needs the IPsec + netfilter kernel modules loaded
    # before it installs any SA (otherwise this kernel crashes) and before
    # NAT rules can be added.
    load_kernel_modules

    install_cert

    # strongswan.conf is only read at charon startup, so if it changed we
    # must restart charon (not just hot-reload swanctl). swanctl.conf, by
    # contrast, is applied live via 'swanctl --load-all'.
    SS_MD5_OLD=$(md5sum "$STRONGSWAN_CONF_OUT" 2>/dev/null | cut -d' ' -f1)
    render_strongswan_conf
    SS_MD5_NEW=$(md5sum "$STRONGSWAN_CONF_OUT" 2>/dev/null | cut -d' ' -f1)
    render_swanctl_conf
    own_pkg "$ETC"

    touch "${ETC}/enabled"
    chmod 644 "${ETC}/enabled" 2>/dev/null
    own_pkg "${ETC}/enabled"

    # log watcher: always runs (structured events for the UI's Log page);
    # DSM auto-block registration inside it is separately gated on
    # IKEV2_AUTOBLOCK
    "${TARGET}/bin/ikev2watch" start

    # start_charon() always stops any existing instance first, so it is the
    # safe path whenever a (re)start is actually needed. Only hot-reload
    # when charon is already up AND its startup config is unchanged.
    if charon_running && [ "$SS_MD5_OLD" = "$SS_MD5_NEW" ]; then
        do_reload
    else
        start_charon
        do_reload
    fi

    # NAT/forwarding so clients reach the internet - added on start,
    # removed on stop (do_remove).
    nat_install

    # The notification tag lives in a DSM cache the package does not own, so
    # it is put back here rather than only at install: this runs on every boot.
    notify_ensure || true

    date '+%Y-%m-%d %H:%M:%S' > "${ETC}/last_applied"
    own_pkg "${ETC}/last_applied"

    log "IKEv2 configuration applied (mschapv2=${IKEV2_ENABLE_MSCHAPV2} psk=${IKEV2_ENABLE_PSK} rsa=${IKEV2_ENABLE_RSA} eaptls=${IKEV2_ENABLE_EAPTLS} autoblock=${IKEV2_AUTOBLOCK})"
}

do_remove() {
    load_settings
    stop_charon
    # tear down the iptables rules we added on start (user requirement:
    # MASQUERADE added when the service runs, removed when it stops).
    nat_remove
    # note: the ${ETC}/enabled flag is kept on purpose - it records the
    # user's intent so start-stop-status can re-apply after a reboot.
    # The management UI's disable action removes it.
    "${TARGET}/bin/ikev2watch" stop >/dev/null 2>&1
    log "IKEv2 daemon stopped"
}

do_status() {
    load_settings

    [ -f "${ETC}/enabled" ] && echo "enabled=yes" || echo "enabled=no"
    if charon_running; then
        echo "charon=yes"
        echo "ike_daemon=charon"
    else
        echo "charon=no"
        echo "ike_daemon=none"
    fi

    if [ -f "${CERT_DIR}/server-cert.pem" ]; then
        echo "cert_cn=$(cert_cn "${CERT_DIR}/server-cert.pem")"
        [ -f "${CERT_DIR}/self-signed" ] && echo "cert_self_signed=yes" || echo "cert_self_signed=no"
        [ -f "${CERT_DIR}/temporary" ] && echo "cert_temporary=yes" || echo "cert_temporary=no"
    fi
    if [ -f "${CLIENTCA_DIR}/ca.pem" ]; then
        echo "clientca_cn=$(cert_cn "${CLIENTCA_DIR}/ca.pem")"
    fi

    echo "hostname=${IKEV2_HOSTNAME}"
    echo "enc=${IKEV2_ENC}"
    set -- $(detect_iface)
    echo "iface_name=${1:-}"
    echo "iface_ip=${2:-}"
    # listen-interface selection + the list of interfaces to choose from
    # (comma-separated "name:ip", for the UI dropdown)
    echo "iface=${IKEV2_IFACE}"
    echo "iface_list=$(list_ifaces | awk '{ printf "%s%s:%s", (n++?",":""), $1, $2 }')"
    echo "listen_addrs=$(listen_addrs)"
    echo "last_applied=$(cat "${ETC}/last_applied" 2>/dev/null)"

    # DNS the NAS itself uses - shown in the UI when a server is set to
    # automatic DNS (empty dns_* value)
    echo "server_dns=$(server_dns)"

    echo "dsm_cert_default=$(dsm_cert_default)"

    echo "mschapv2=${IKEV2_ENABLE_MSCHAPV2}"
    echo "subnet_mschapv2=${IKEV2_SUBNET_MSCHAPV2}"
    echo "dns_mschapv2=${IKEV2_DNS_MSCHAPV2}"
    echo "cert_mschapv2=${IKEV2_CERT_MSCHAPV2}"

    echo "psk_enabled=${IKEV2_ENABLE_PSK}"
    echo "psk=${IKEV2_PSK}"
    echo "subnet_psk=${IKEV2_SUBNET_PSK}"
    echo "dns_psk=${IKEV2_DNS_PSK}"

    echo "rsa_enabled=${IKEV2_ENABLE_RSA}"
    echo "subnet_rsa=${IKEV2_SUBNET_RSA}"
    echo "dns_rsa=${IKEV2_DNS_RSA}"
    echo "cert_rsa=${IKEV2_CERT_RSA}"

    echo "eaptls_enabled=${IKEV2_ENABLE_EAPTLS}"
    echo "subnet_eaptls=${IKEV2_SUBNET_EAPTLS}"
    echo "dns_eaptls=${IKEV2_DNS_EAPTLS}"
    echo "cert_eaptls=${IKEV2_CERT_EAPTLS}"

    # DSM-account MSCHAPv2: how many active DSM accounts would be registered
    # (NT hashes read live from synosmbpasswd.conf, disabled/empty excluded)
    echo "dsm_accounts=$(dsm_ntlm_secrets 2>/dev/null | grep -c '^    ntlm-')"

    echo "autoblock=${IKEV2_AUTOBLOCK}"
    "${TARGET}/bin/ikev2watch" status 2>/dev/null

    # plugin availability - our own bundled charon build (fixed feature
    # set, compiled with eap-identity/eap-mschapv2/eap-radius/eap-tls)
    if charon_running; then
        LOADED=$(swanctl --list-plugins 2>/dev/null)
        printf '%s' "$LOADED" | grep -qw "eap-tls"      && echo "plugin_eap_tls=yes"      || echo "plugin_eap_tls=no"
        printf '%s' "$LOADED" | grep -qw "eap-radius"    && echo "plugin_eap_radius=yes"    || echo "plugin_eap_radius=no"
        printf '%s' "$LOADED" | grep -qw "eap-mschapv2"  && echo "plugin_eap_mschapv2=yes"  || echo "plugin_eap_mschapv2=no"
    else
        echo "plugin_eap_tls=unknown"
        echo "plugin_eap_radius=unknown"
        echo "plugin_eap_mschapv2=unknown"
    fi

    CERTS=0
    [ -d "$ISSUED_DIR" ] && CERTS=$(find "$ISSUED_DIR" -name '*.pem' 2>/dev/null | wc -l | tr -d ' ')
    echo "certs=${CERTS}"

    CONNS=$(list_connections)
    TOTAL=0; C_MSCHAPV2=0; C_PSK=0; C_RSA=0; C_EAPTLS=0
    if [ -n "$CONNS" ]; then
        TOTAL=$(printf '%s\n' "$CONNS" | grep -c .)
        C_MSCHAPV2=$(printf '%s\n' "$CONNS" | grep -c '^ikev2|')
        C_PSK=$(printf '%s\n' "$CONNS" | grep -c '^ikev2-psk|')
        C_RSA=$(printf '%s\n' "$CONNS" | grep -c '^ikev2-rsa|')
        C_EAPTLS=$(printf '%s\n' "$CONNS" | grep -c '^ikev2-eaptls|')
    fi
    echo "connections=${TOTAL}"
    echo "connections_mschapv2=${C_MSCHAPV2}"
    echo "connections_psk=${C_PSK}"
    echo "connections_rsa=${C_RSA}"
    echo "connections_eaptls=${C_EAPTLS}"
}

do_clients() {
    CONNS=$(list_connections)
    if [ -z "$CONNS" ]; then
        echo "(no active sessions)"
        return 0
    fi
    printf 'conn|peer_ip|virtual_ip|state\n%s\n' "$CONNS"
}

do_log_dump() {
    cat "$LOG" 2>/dev/null
}
