# dsmuser.sh - DSM local accounts for EAP-MSCHAPv2.
#
# DSM keeps every local account's NT hash (MD4 of the password) in a
# DSM-native file, one "USERNAME=NThash" line per account under a
# [smbpasswd] section. strongSwan's swanctl.conf 'ntlm' secret type takes
# that NT hash directly, so DSM accounts can log in over IKEv2/EAP-MSCHAPv2
# using their existing DSM password.

SYNOSMB_CONF="/usr/syno/etc/synosmbpasswd.conf"
SYNOUSER_BIN="/usr/syno/sbin/synouser"
# NT hash of an empty password - accounts left at this value have no
# password set (e.g. DSM's disabled default admin); never register them.
EMPTY_NT_HASH="31D6CFE0D16AE931B73C59D7E0C089C0"

# true if a DSM account may use the VPN. With no allowlist file, every account
# is allowed (the caller's own empty/expired filters still exclude unusable
# ones); once the Privileges page has been applied, only listed names pass.
dsm_user_allowed() {
    [ -f "$VPNUSERS" ] || return 0
    grep -qxF "$1" "$VPNUSERS"
}

# Emit swanctl 'ntlm' secret blocks for the active DSM accounts, read fresh
# from synosmbpasswd.conf every time the config is rendered (i.e. every
# service start / apply), so new accounts and password changes are picked up.
#
# synosmbpasswd.conf stores usernames upper-cased; the real DSM login name
# (correct case, which is what the client sends as its EAP identity) comes
# from /etc/passwd (uid >= 1024). We iterate the real accounts, look their
# NT hash up by upper-cased name, and skip any account that has no hash, has
# the empty-password hash, or is expired/disabled in DSM.
dsm_ntlm_secrets() {
    [ -r "$SYNOSMB_CONF" ] || { log "WARN: $SYNOSMB_CONF not readable - no DSM accounts registered"; return 0; }
    awk -F: '$3>=1024 && $3<60000 {print $1}' /etc/passwd 2>/dev/null | while read -r U; do
        [ -n "$U" ] || continue
        dsm_user_allowed "$U" || continue
        UP=$(printf '%s' "$U" | tr '[:lower:]' '[:upper:]')
        HASH=$(awk -F= -v u="$UP" '/^\[/{s=0} /^\[smbpasswd\]/{s=1} s && $1==u {print $2}' "$SYNOSMB_CONF")
        [ -n "$HASH" ] || continue
        HUP=$(printf '%s' "$HASH" | tr '[:lower:]' '[:upper:]')
        [ "$HUP" = "$EMPTY_NT_HASH" ] && continue
        if [ -x "$SYNOUSER_BIN" ]; then
            "$SYNOUSER_BIN" --get "$U" 2>/dev/null | grep -qi 'Expired *: *\[true\]' && continue
        fi
        UESC=$(printf '%s' "$U" | sed 's/"/\\"/g')
        printf '    ntlm-%s {\n        id = "%s"\n        secret = 0x%s\n    }\n' "$U" "$UESC" "$HUP"
    done
}

# List every DSM local account for the Privileges page, one
# "name|status|allowed" line each:
#   status  = normal  (has a real password, not expired/disabled)
#           | disabled (no NT hash, empty-password hash, or expired in DSM)
#   allowed = yes|no   membership in the VPN allowlist; with no allowlist file
#                      yet, normal accounts default to yes, disabled to no.
dsm_users_list() {
    [ -r "$SYNOSMB_CONF" ] || return 0
    awk -F: '$3>=1024 && $3<60000 {print $1}' /etc/passwd 2>/dev/null | while read -r U; do
        [ -n "$U" ] || continue
        UP=$(printf '%s' "$U" | tr '[:lower:]' '[:upper:]')
        HASH=$(awk -F= -v u="$UP" '/^\[/{s=0} /^\[smbpasswd\]/{s=1} s && $1==u {print $2}' "$SYNOSMB_CONF")
        HUP=$(printf '%s' "$HASH" | tr '[:lower:]' '[:upper:]')
        ST="normal"
        if [ -z "$HASH" ] || [ "$HUP" = "$EMPTY_NT_HASH" ]; then
            ST="disabled"
        elif [ -x "$SYNOUSER_BIN" ] && "$SYNOUSER_BIN" --get "$U" 2>/dev/null | grep -qi 'Expired *: *\[true\]'; then
            ST="disabled"
        fi
        if [ -f "$VPNUSERS" ]; then
            if grep -qxF "$U" "$VPNUSERS"; then A="yes"; else A="no"; fi
        else
            [ "$ST" = "normal" ] && A="yes" || A="no"
        fi
        printf '%s|%s|%s\n' "$U" "$ST" "$A"
    done
}
