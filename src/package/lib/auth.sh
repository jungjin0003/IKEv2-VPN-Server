# auth.sh - the DSM session check the web entry points run before anything else.
#
# DSM symlinks target/ui into its web root and does not gate what it serves
# from there: /webman/3rdparty/IKEv2VPN/ answers anyone who can reach the web
# port, logged in or not. A third-party package has to establish the session
# itself, so every CGI in ui/ sources this file and calls web_authenticate
# before it parses a request, reads a setting or loads a handler.
#
# The session is established by DSM's own authenticate.cgi, which with DSM's
# cross-site request forgery protection switched on answers only when the
# request carries the session's SynoToken - and DSM does not put that token on
# the URL it launches a third-party package with. So the first request cannot
# have one. index.cgi answers that request with a bootstrap page that displays
# nothing: it obtains the token and puts it in a cookie, or hands the browser to
# DSM when there is no session to obtain one from. From there every later
# request carries the cookie, including the module imports that a query string
# cannot survive.
#
# This file lives outside ui/ on purpose - nothing under ui/ is private.

SYNO_AUTH="/usr/syno/synoman/webman/modules/authenticate.cgi"
SYNO_LOGIN="/webman/index.cgi?launchApp=SYNO.SDS.IKEv2VPN.Application"
# DSM without the launch request. Going here does not bring the browser back,
# which is what makes it the safe destination when this app is what cannot be
# reached - see the second attempt in index.cgi's bootstrap.
SYNO_DESKTOP="/webman/index.cgi"
ADMIN_GROUP="administrators"

TOKEN_COOKIE="IKEV2VPN_SynoToken"
COOKIE_PATH="/webman/3rdparty/IKEv2VPN/"

# Set by web_authenticate on success.
AUTH_USER=""
AUTH_TOKEN=""

# The caller has already reduced the name to [A-Za-z0-9._-], so it carries no
# pattern character and can be matched as one.
dsm_is_admin() {
    _members=$(sed -n "s/^${ADMIN_GROUP}:[^:]*:[^:]*://p" /etc/group 2>/dev/null | head -n 1)
    [ -n "$_members" ] || return 1
    case ",${_members}," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

# web_token [explicit] - find this request's SynoToken, setting AUTH_TOKEN.
#
# Four places, in order: one the caller passes, the header the page's own calls
# set, the query string, and the cookie the bootstrap wrote. Each is checked on
# its own and a malformed one is stepped over rather than being fatal - a stale
# ?SynoToken= left in a bookmark must not stop the good cookie underneath it
# from being used. Succeeds only when one of them was well formed; "none" is a
# different answer from "wrong", and the entry points act on the difference.
web_token() {
    AUTH_TOKEN=""
    for _t in \
        "${1:-}" \
        "${HTTP_X_SYNO_TOKEN:-}" \
        "$(printf '%s' "${QUERY_STRING:-}" | tr '&' '\n' \
           | sed -n 's/^SynoToken=//p' | head -n 1)" \
        "$(printf '%s' "${HTTP_COOKIE:-}" | tr ';' '\n' \
           | sed -n "s/^[[:space:]]*${TOKEN_COOKIE}=//p" | head -n 1)"
    do
        case "$_t" in
            "" | *[!A-Za-z0-9._-]*) continue ;;
        esac
        AUTH_TOKEN="$_t"
        return 0
    done
    return 1
}

# Header that drops the token cookie, for when the one we have is refused.
web_clear_token_cookie() {
    printf 'Set-Cookie: %s=; Path=%s; Max-Age=0; SameSite=Strict%s\r\n' \
        "$TOKEN_COOKIE" "$COOKIE_PATH" "$(web_cookie_secure)"
}

web_cookie_secure() {
    case "${HTTPS:-}" in
        on|ON|1) printf '; Secure' ;;
    esac
}

# web_authenticate [synotoken] - succeeds only for a logged-in DSM administrator.
#
#   0  authorised, AUTH_USER holds the login name
#   1  a token was presented and refused - no session, or a stale token
#   2  there is a session, but not an administrator's; redirecting this caller
#      to the login page would only bring them straight back here, so the entry
#      point refuses instead
#   3  no token at all - authenticate.cgi cannot even be asked
web_authenticate() {
    AUTH_USER=""
    [ -x "$SYNO_AUTH" ] || return 1

    # With DSM's cross-site request forgery protection on, authenticate.cgi
    # answers only when the token is there; with it off it answers without one.
    # It is asked either way, and "there was no token to offer" is kept apart
    # from "the token was refused" - only the first is worth sending the
    # browser off to fetch one.
    if web_token "${1:-}"; then
        _q="SynoToken=${AUTH_TOKEN}"
        _fail=1
    else
        _q=""
        _fail=3
    fi

    # Only the token is handed over: our own parameters are none of its
    # business, stdin is closed so it cannot consume a body we have read or are
    # about to read, and the method is fixed so it does not wait for one.
    _u=$(QUERY_STRING="$_q" \
         REQUEST_METHOD="GET" \
         CONTENT_LENGTH="" \
         "$SYNO_AUTH" 2>/dev/null </dev/null | tr -d '\r\n')

    # empty means no session; anything outside a plain login name means we did
    # not get what we think we got, and is refused rather than interpreted
    case "$_u" in
        "" | *[!A-Za-z0-9._-]*) return "$_fail" ;;
    esac

    dsm_is_admin "$_u" || return 2

    AUTH_USER="$_u"
    return 0
}
