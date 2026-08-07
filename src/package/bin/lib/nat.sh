# nat.sh - NAT / forwarding for the client subnets.
#
# charon installs the IPsec SA, but the client's traffic still needs the
# NAS to route+NAT it out to the internet. VPN Server/VPNCenter normally
# sets this up; standalone we must. Rules are added on apply (when the
# service starts) and removed on remove (when it stops), per user request.
#
# We put ALL our rules in dedicated custom chains (NAT_CHAIN / FWD_CHAIN)
# and only jump into them from the built-in POSTROUTING/FORWARD. Teardown
# then just deletes those two jumps and flushes/deletes our chains -
# removing exactly our rules and nothing else. This also avoids `-m
# comment` (xt_comment), which is NOT available on this DSM kernel.

NAT_CHAIN="IKEV2VPN_MASQ"
FWD_CHAIN="IKEV2VPN_FWD"
MSS_CHAIN="IKEV2VPN_MSS"

# TCP MSS to clamp forwarded client SYN/SYN-ACK down to. This is policy-based
# IPsec with no virtual tunnel interface, so the forwarded inner packet routes
# out the physical egress (MTU 1500) and --clamp-mss-to-pmtu would only ever
# see 1500 - it cannot account for the ~70+ bytes of ESP + NAT-T overhead the
# packet gains after encryption. So we clamp to a fixed value instead. 1360
# keeps the post-encapsulation packet comfortably under a 1500 path and fixes
# the "tunnel connects but TCP stalls / web won't load while DNS works"
# symptom. Lower it (e.g. 1280) if a small-MTU cellular path still stalls.
MSS_VALUE=1360

# detected egress interface (the one with the default route to the internet)
egress_iface() {
    ip -4 route get 8.8.8.8 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n 1
}

# list of client subnets for auth methods that are enabled (settings loaded)
enabled_subnets() {
    [ "$IKEV2_ENABLE_MSCHAPV2" = "yes" ] && echo "$IKEV2_SUBNET_MSCHAPV2"
    [ "$IKEV2_ENABLE_PSK" = "yes" ]      && echo "$IKEV2_SUBNET_PSK"
    [ "$IKEV2_ENABLE_RSA" = "yes" ]      && echo "$IKEV2_SUBNET_RSA"
    [ "$IKEV2_ENABLE_EAPTLS" = "yes" ]   && echo "$IKEV2_SUBNET_EAPTLS"
}

nat_install() {
    [ "$(id -u)" = "0" ] || return 0
    command -v iptables >/dev/null 2>&1 || { log "WARN: iptables not found - client internet will not work"; return 0; }
    IFACE=$(egress_iface)
    [ -n "$IFACE" ] || { log "WARN: could not detect egress interface for NAT"; return 0; }

    echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null

    # start clean so re-apply never duplicates
    nat_remove_quiet

    # create our chains and hook them in. Insert the jumps at the TOP of the
    # built-in chains (-I ... 1) rather than appending, so our rules take
    # priority over whatever DSM or other packages have already installed -
    # e.g. a broad FORWARD DROP/REJECT would otherwise run first and block
    # the client traffic before our ACCEPT is ever reached.
    iptables -t nat -N "$NAT_CHAIN" 2>/dev/null
    iptables -N "$FWD_CHAIN" 2>/dev/null
    iptables -t mangle -N "$MSS_CHAIN" 2>/dev/null
    iptables -t nat -I POSTROUTING 1 -j "$NAT_CHAIN" 2>/dev/null
    iptables -I FORWARD 1 -j "$FWD_CHAIN" 2>/dev/null
    iptables -t mangle -I FORWARD 1 -j "$MSS_CHAIN" 2>/dev/null

    for net in $(enabled_subnets); do
        [ -n "$net" ] || continue
        iptables -t nat -A "$NAT_CHAIN" -s "$net" -o "$IFACE" -j MASQUERADE 2>/dev/null
        iptables -A "$FWD_CHAIN" -s "$net" -j ACCEPT 2>/dev/null
        iptables -A "$FWD_CHAIN" -d "$net" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
        # Clamp TCP MSS on connection setup packets to/from the client. The
        # SYN,RST SYN match hits both the client's SYN (-s) and the server's
        # returning SYN-ACK (-d), so both ends negotiate a small-enough MSS
        # and full-size segments never get dropped inside the tunnel.
        iptables -t mangle -A "$MSS_CHAIN" -s "$net" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS_VALUE" 2>/dev/null
        iptables -t mangle -A "$MSS_CHAIN" -d "$net" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS_VALUE" 2>/dev/null
    done
    log "NAT/forwarding installed (egress ${IFACE})"
}

# remove the jumps, then flush+delete our chains. Silent/idempotent.
nat_remove_quiet() {
    [ "$(id -u)" = "0" ] || return 0
    command -v iptables >/dev/null 2>&1 || return 0
    # delete any jump(s) into our chains (loop in case of duplicates)
    while iptables -t nat -C POSTROUTING -j "$NAT_CHAIN" 2>/dev/null; do
        iptables -t nat -D POSTROUTING -j "$NAT_CHAIN" 2>/dev/null || break
    done
    while iptables -C FORWARD -j "$FWD_CHAIN" 2>/dev/null; do
        iptables -D FORWARD -j "$FWD_CHAIN" 2>/dev/null || break
    done
    while iptables -t mangle -C FORWARD -j "$MSS_CHAIN" 2>/dev/null; do
        iptables -t mangle -D FORWARD -j "$MSS_CHAIN" 2>/dev/null || break
    done
    iptables -t nat -F "$NAT_CHAIN" 2>/dev/null
    iptables -t nat -X "$NAT_CHAIN" 2>/dev/null
    iptables -F "$FWD_CHAIN" 2>/dev/null
    iptables -X "$FWD_CHAIN" 2>/dev/null
    iptables -t mangle -F "$MSS_CHAIN" 2>/dev/null
    iptables -t mangle -X "$MSS_CHAIN" 2>/dev/null
}

nat_remove() {
    nat_remove_quiet
    log "NAT/forwarding removed"
}
