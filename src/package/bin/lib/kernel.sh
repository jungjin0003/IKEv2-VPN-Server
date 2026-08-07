# kernel.sh - IPsec/netfilter kernel module loading.
#
# We run charon standalone (no VPN Server/VPNCenter), so nothing else has
# loaded the kernel's IPsec (XFRM) and netfilter/NAT modules for us. On
# this DSM/Xpenology kernel, charon installing an ESP SA into an
# uninitialised XFRM stack takes the whole box down - so these MUST be
# loaded (in dependency order) before charon starts and before we add NAT
# rules. Prefer the system copies under /lib/modules (always match the
# running kernel); fall back to the arch-specific set bundled in the
# package only if a module is missing from the system.

# IPsec datapath, then netfilter/NAT - order matters (deps first).
IPSEC_MODS="xfrm_algo xfrm_user af_key ah4 esp4 tunnel4 xfrm4_tunnel xfrm4_mode_tunnel xfrm4_mode_transport"
NAT_MODS="x_tables ip_tables nf_conntrack nf_defrag_ipv4 nf_conntrack_ipv4 iptable_filter nf_nat nf_nat_ipv4 iptable_nat nf_nat_masquerade_ipv4 ipt_MASQUERADE"

# Load one module by name from the running DSM firmware's own module set.
# Already-loaded or absent-everywhere modules are non-fatal (some kernels
# fold functionality into others or built it in).
load_one_mod() {
    _m="$1"
    # already loaded?
    grep -q "^${_m} " /proc/modules 2>/dev/null && return 0
    # prefer modprobe (resolves dependencies) when available
    if command -v modprobe >/dev/null 2>&1; then
        modprobe "$_m" 2>/dev/null && return 0
    fi
    for _f in "/lib/modules/${_m}.ko" "/usr/lib/modules/${_m}.ko"; do
        if [ -f "$_f" ]; then
            insmod "$_f" 2>/dev/null && return 0
        fi
    done
    return 1
}

load_kernel_modules() {
    [ "$(id -u)" = "0" ] || return 0
    for _m in $IPSEC_MODS $NAT_MODS; do
        load_one_mod "$_m" || true
    done
    # esp4 is the one that actually matters for the tunnel - warn if absent
    if ! grep -q "^esp4 " /proc/modules 2>/dev/null \
       && ! grep -q "^esp " /proc/modules 2>/dev/null; then
        log "WARN: esp4 kernel module not loaded - IPsec tunnels may fail"
    fi
}
