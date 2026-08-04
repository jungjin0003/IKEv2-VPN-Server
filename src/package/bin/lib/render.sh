# render.sh - generate the two strongSwan config files from the settings.

# cipher proposals for the current IKEV2_ENC setting.
# - ecp* (EC curve DH groups) deliberately excluded: the bundled build was
#   not compiled with --enable-ecp, so charon has no such group registered
#   and rejects the whole proposal ("invalid value for: proposals") if one
#   is listed - modp groups (via --enable-gmp, which is compiled in) only.
# - 3des deliberately excluded too: obsolete, and would need a separate
#   --enable-des plugin the bundled build doesn't have either. Every
#   client we care about (Windows/iOS/macOS/Android/strongSwan) supports
#   AES, so there is no real fallback need for it.
cipher_ike() {
    case "$IKEV2_ENC" in
        aes256) echo "aes256-sha256-modp2048,aes256-sha1-modp2048" ;;
        aes128) echo "aes128-sha256-modp2048,aes128-sha1-modp1024" ;;
        *)      echo "aes256-sha256-modp2048,aes256-sha1-modp2048,aes256-sha1-modp1024,aes128-sha1-modp1024" ;;
    esac
}

# ESP (child SA) proposals - deliberately AES-CBC + HMAC-SHA ONLY, no
# AES-GCM/AEAD. On this DSM/Xpenology kernel, installing an AES-GCM ESP SA
# into the XFRM stack takes the whole box down (the GCM/AEAD kernel crypto
# path isn't set up), whereas AES-CBC SAs install fine - the one config
# that reached the internet without crashing negotiated AES_CBC-256. Do
# not add gcm here unless the target kernel is known to handle it.
cipher_esp() {
    case "$IKEV2_ENC" in
        aes256) echo "aes256-sha256,aes256-sha1" ;;
        aes128) echo "aes128-sha256,aes128-sha1" ;;
        *)      echo "aes256-sha256,aes256-sha1,aes128-sha1" ;;
    esac
}

# render ${ETC}/strongswan.conf - main daemon config, points at the
# read-only per-plugin toggle files shipped in target/strongswan/strongswan.d
render_strongswan_conf() {
    mkdir -p "$ETC"
    {
        echo "charon {"
        echo "    load_modular = no"
        # This DSM/Xpenology kernel goes down if charon installs its own
        # routes / virtual IPs into the (fragile) XFRM stack. We do the
        # routing/NAT ourselves (nat_install), so tell charon not to.
        echo "    install_routes = no"
        echo "    install_virtual_ip = no"
        # send_cert=always makes every IKE_AUTH response carry the full
        # certificate chain, so the response is IKE-fragmented (RFC 7383).
        # charon's default fragment size (1280) plus IP/UDP/non-ESP headers
        # exceeds the path MTU on many cellular links (CGNAT / IPv6 min-MTU
        # 1280), where each fragment is then IP-fragmented and the mobile
        # carrier drops the fragmented UDP - the client never sees the
        # response and retransmits IKE_AUTH forever. Shrink the IKE fragment
        # so each one fits (1200 + 4 + 8 + 20 = 1232 < 1280) without any
        # IP-level fragmentation. LAN clients are unaffected.
        echo "    fragment_size = 1200"
        echo "    filelog {"
        echo "        charon {"
        echo "            path = ${CHARON_LOG}"
        echo "            time_format = %Y-%m-%d %H:%M:%S"
        echo "            append = yes"
        echo "            flush_line = yes"
        echo "            default = 1"
        echo "            ike_name = yes"
        echo "        }"
        echo "    }"
        echo "    plugins {"
        echo "        include ${STRONGSWAN_D}/charon/*.conf"
        echo "        kernel-netlink {"
        echo "            install_routes = no"
        echo "        }"
        echo "        vici {"
        echo "            load = yes"
        echo "            socket = unix://${CHARON_VICI}"
        echo "        }"
        echo "    }"
        echo "}"
        # separate from charon.plugins.vici.socket (where charon listens) -
        # this tells the swanctl CLI where to connect TO. Without it,
        # swanctl falls back to its compiled-in default (unix:///var/run/
        # charon.vici), which does not exist here, and every
        # 'swanctl --load-all' silently fails - so connections never
        # actually get loaded into charon.
        echo "swanctl {"
        echo "    socket = unix://${CHARON_VICI}"
        echo "}"
    } > "$STRONGSWAN_CONF_OUT"
    chmod 600 "$STRONGSWAN_CONF_OUT"
}

# effective DNS for a pool: the stored value if set (manual DNS), otherwise
# the NAS's own resolvers (automatic DNS).
pool_dns() { [ -n "$1" ] && printf '%s\n' "$1" || server_dns; }

# address range to hand out from a /24 client pool. strongSwan would otherwise
# assign the very first address (x.x.x.1); the iOS built-in IKEv2 client is
# known to establish the tunnel but never route data when handed x.x.x.1, so
# start the pool at .2. Non-/24 values pass through unchanged.
pool_range() {
    case "$1" in
        *.0/24) _pfx=${1%.0/24}; printf '%s.2-%s.254\n' "$_pfx" "$_pfx" ;;
        *)      printf '%s\n' "$1" ;;
    esac
}

# render ${ETC}/swanctl/swanctl.conf - connection/pool/secret definitions,
# loaded live via 'swanctl --load-all' (no daemon restart needed)
render_swanctl_conf() {
    get_leftid
    mkdir -p "$SWANCTL_ETC"

    # per-scope IKE identity = CN of that server's chosen certificate (written
    # by install_server_cert); fall back to the global leftid
    LEFTID_MSCHAPV2=$(cat "${CERT_DIR}/mschapv2.leftid" 2>/dev/null); [ -n "$LEFTID_MSCHAPV2" ] || LEFTID_MSCHAPV2="$LEFTID"
    LEFTID_RSA=$(cat "${CERT_DIR}/rsa.leftid" 2>/dev/null);           [ -n "$LEFTID_RSA" ]      || LEFTID_RSA="$LEFTID"
    LEFTID_EAPTLS=$(cat "${CERT_DIR}/eaptls.leftid" 2>/dev/null);     [ -n "$LEFTID_EAPTLS" ]   || LEFTID_EAPTLS="$LEFTID"

    # local_addrs = concrete interface IP(s), never the literal %any (which
    # this fragile kernel dislikes when combined with charon route/vip
    # install). Default (IKEV2_IFACE="") binds every real IPv4 address so the
    # server is reachable on all interfaces; a specific IKEV2_IFACE narrows it
    # to that one. listen_addrs() falls back to %any only if nothing is found.
    LOCAL_ADDR=$(listen_addrs)

    CONNS=""
    POOLS=""
    SECRETS=""

    if [ "$IKEV2_ENABLE_MSCHAPV2" = "yes" ]; then
        # DSM accounts only: users authenticate over EAP-MSCHAPv2 with their
        # existing DSM password. The credential comes from the DSM NT hashes
        # emitted as 'ntlm' secrets below (filtered by the Privileges allowlist).
        RAUTH="eap-mschapv2"
        CONNS="${CONNS}
    ikev2 {
        version = 2
        local_addrs = ${LOCAL_ADDR}
        remote_addrs = %any
        proposals = $(cipher_ike)
        fragmentation = yes
        encap = yes
        dpd_delay = 30s
        pools = pool-ikev2
        send_cert = always
        local {
            auth = pubkey
            certs = server-cert-mschapv2.pem
            id = \"${LEFTID_MSCHAPV2}\"
        }
        remote {
            auth = ${RAUTH}
            eap_id = %any
        }
        children {
            ikev2 {
                mode = tunnel
                local_ts = 0.0.0.0/0
                esp_proposals = $(cipher_esp)
                rekey_time = 0
            }
        }
    }"
        POOLS="${POOLS}
    pool-ikev2 {
        addrs = $(pool_range "$IKEV2_SUBNET_MSCHAPV2")
        dns = $(pool_dns "$IKEV2_DNS_MSCHAPV2")
    }"

        SECRETS="${SECRETS}
    private-server-mschapv2 { file = server-key-mschapv2.pem }
$(dsm_ntlm_secrets)"
    fi

    if [ "$IKEV2_ENABLE_PSK" = "yes" ] && [ -n "$IKEV2_PSK" ]; then
        CONNS="${CONNS}
    ikev2-psk {
        version = 2
        local_addrs = ${LOCAL_ADDR}
        remote_addrs = %any
        proposals = $(cipher_ike)
        fragmentation = yes
        encap = yes
        dpd_delay = 30s
        pools = pool-ikev2-psk
        local {
            auth = psk
            id = \"${LEFTID}\"
        }
        remote {
            auth = psk
        }
        children {
            ikev2-psk {
                mode = tunnel
                local_ts = 0.0.0.0/0
                esp_proposals = $(cipher_esp)
                rekey_time = 0
            }
        }
    }"
        POOLS="${POOLS}
    pool-ikev2-psk {
        addrs = $(pool_range "$IKEV2_SUBNET_PSK")
        dns = $(pool_dns "$IKEV2_DNS_PSK")
    }"
        PSKESC=$(printf '%s' "$IKEV2_PSK" | sed 's/"/\\"/g')
        SECRETS="${SECRETS}
    ike-psk { secret = \"${PSKESC}\" }"
    fi

    if [ "$IKEV2_ENABLE_RSA" = "yes" ]; then
        ensure_client_ca
        CONNS="${CONNS}
    ikev2-rsa {
        version = 2
        local_addrs = ${LOCAL_ADDR}
        remote_addrs = %any
        proposals = $(cipher_ike)
        fragmentation = yes
        encap = yes
        dpd_delay = 30s
        pools = pool-ikev2-rsa
        send_cert = always
        local {
            auth = pubkey
            certs = server-cert-rsa.pem
            id = \"${LEFTID_RSA}\"
        }
        remote {
            auth = pubkey
            cacerts = clientca.pem
        }
        children {
            ikev2-rsa {
                mode = tunnel
                local_ts = 0.0.0.0/0
                esp_proposals = $(cipher_esp)
                rekey_time = 0
            }
        }
    }"
        POOLS="${POOLS}
    pool-ikev2-rsa {
        addrs = $(pool_range "$IKEV2_SUBNET_RSA")
        dns = $(pool_dns "$IKEV2_DNS_RSA")
    }"
        SECRETS="${SECRETS}
    private-server-rsa { file = server-key-rsa.pem }"
    fi

    if [ "$IKEV2_ENABLE_EAPTLS" = "yes" ]; then
        ensure_client_ca
        CONNS="${CONNS}
    ikev2-eaptls {
        version = 2
        local_addrs = ${LOCAL_ADDR}
        remote_addrs = %any
        proposals = $(cipher_ike)
        fragmentation = yes
        encap = yes
        dpd_delay = 30s
        pools = pool-ikev2-eaptls
        send_cert = always
        local {
            auth = pubkey
            certs = server-cert-eaptls.pem
            id = \"${LEFTID_EAPTLS}\"
        }
        remote {
            auth = eap-tls
            eap_id = %any
            cacerts = clientca.pem
        }
        children {
            ikev2-eaptls {
                mode = tunnel
                local_ts = 0.0.0.0/0
                esp_proposals = $(cipher_esp)
                rekey_time = 0
            }
        }
    }"
        POOLS="${POOLS}
    pool-ikev2-eaptls {
        addrs = $(pool_range "$IKEV2_SUBNET_EAPTLS")
        dns = $(pool_dns "$IKEV2_DNS_EAPTLS")
    }"
        SECRETS="${SECRETS}
    private-server-eaptls { file = server-key-eaptls.pem }"
    fi

    umask 077
    {
        echo "connections {${CONNS}"
        echo "}"
        echo "pools {${POOLS}"
        echo "}"
        echo "secrets {"
        echo "${SECRETS}"
        echo "}"
    } > "$SWANCTL_CONF_OUT"
    chmod 600 "$SWANCTL_CONF_OUT"
}
