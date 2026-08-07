# profile.sh - client profile / CA certificate downloads.

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
