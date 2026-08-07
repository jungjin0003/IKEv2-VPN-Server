# net.sh - interface / address / resolver discovery on the NAS itself.

# detected default-route interface name + its IP (informational: shown in the
# UI as the internet-egress interface used for NAT)
detect_iface() {
    ip -4 route get 1.1.1.1 2>/dev/null \
        | sed -n 's/.* dev \([^ ]*\).*src \([^ ]*\).*/\1 \2/p' | head -n 1
}

# real (non-loopback) global-scope IPv4 interfaces, one "name ip" per line.
list_ifaces() {
    ip -o -4 addr show scope global 2>/dev/null \
        | awk '{ split($4, a, "/"); if ($2 != "lo") print $2, a[1] }'
}

# the swanctl.conf 'local_addrs' value, honoring the IKEV2_IFACE setting:
#   ""        -> ALL real IPv4 addresses, comma-joined (listen everywhere).
#                On a single-NIC box this is just that one LAN IP - i.e. a
#                concrete pinned address, NOT the literal %any (which this
#                fragile kernel dislikes). %any is only a last-resort fallback.
#   <ifname>  -> only that interface's IPv4 address(es).
listen_addrs() {
    _sel="$IKEV2_IFACE"
    if [ -n "$_sel" ]; then
        _a=$(ip -o -4 addr show dev "$_sel" scope global 2>/dev/null \
             | awk '{ split($4,x,"/"); printf "%s%s", (n++?",":""), x[1] }')
        [ -n "$_a" ] && { echo "$_a"; return; }
        # selected interface currently has no IPv4 - fall through to "all"
    fi
    _all=$(list_ifaces | awk '{ printf "%s%s", (n++?",":""), $2 }')
    [ -n "$_all" ] && { echo "$_all"; return; }
    echo "%any"
}

# resolvers the NAS itself uses - pushed to clients when a server is set to
# "automatic DNS" (its stored DNS value is empty). Comma-separated, up to 3;
# falls back to a public resolver if /etc/resolv.conf has none.
server_dns() {
    _d=$(awk '/^[Nn]ameserver[ \t]/ && $2 ~ /^[0-9]+(\.[0-9]+){3}$/ {a=a (a?",":"") $2; n++} n>=3{exit} END{print a}' /etc/resolv.conf 2>/dev/null)
    [ -n "$_d" ] && printf '%s\n' "$_d" || printf '8.8.8.8\n'
}
