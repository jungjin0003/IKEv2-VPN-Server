# release.sh - is there a newer release than the installed one?
#
# The lookup sits here rather than inside the api.cgi handler so that it is
# not tied to the page: it is a shell module under bin/lib like the rest of
# the package's own code, and the handler sources it. The answer is cached,
# so however many times the question is put, GitHub is asked at most once an
# hour.
#
# Only the tag name is taken from the response. Everything else is discarded.
#
# Paths are derived here rather than taken from common.sh, since not every
# caller loads it.

RELEASE_PKG="IKEv2VPN"
RELEASE_PKG_DIR="${PKG_DIR:-/var/packages/${RELEASE_PKG}}"
RELEASE_VAR="${VAR:-${RELEASE_PKG_DIR}/var}"

RELEASE_API_URL="https://api.github.com/repos/jungjin0003/IKEv2-VPN-Server/releases/latest"
RELEASE_OK_CACHE="${RELEASE_VAR}/release-latest.cache"
RELEASE_FAIL_CACHE="${RELEASE_VAR}/release-latest.fail"
RELEASE_LOCK="${RELEASE_VAR}/release-latest.lock"

# How stale an answer may be before GitHub is asked again. This is the real
# request rate: everything else only decides how often the clock is read.
RELEASE_OK_TTL=3600
RELEASE_FAIL_TTL=3600

RELEASE_PKG_USER="sc-ikev2vpn"

# The cache is written by whoever asks first - root from the watcher, the
# package user from the page - and has to stay readable to the other.
release_own() {
    chmod 644 "$1" 2>/dev/null
    [ "$(id -u)" = "0" ] || return 0
    _release_owner=$(stat -c '%U' "$RELEASE_VAR" 2>/dev/null)
    [ -n "$_release_owner" ] && [ "$_release_owner" != "root" ] ||
        _release_owner="$RELEASE_PKG_USER"
    chown "$_release_owner" "$1" 2>/dev/null
}

release_version() {
    _release_normalized=${1#v}
    case "$_release_normalized" in ''|*[!0-9.-]*) return 1 ;; esac
    printf '%s' "$_release_normalized" |
        grep -Eq '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}(-[0-9]{1,9})?$' || return 1
    printf '%s\n' "$_release_normalized"
}

release_current_version() {
    [ -r "${RELEASE_PKG_DIR}/INFO" ] || return 1
    _release_version=$(sed -n \
        's/^version="\{0,1\}\([^"[:space:]]*\)"\{0,1\}$/\1/p' \
        "${RELEASE_PKG_DIR}/INFO" | head -n 1)
    release_version "$_release_version"
}

release_number() {
    _release_number=$(printf '%s' "$1" | sed 's/^0*//')
    printf '%s\n' "${_release_number:-0}"
}

release_is_newer() {
    _release_left=$(release_version "$1") || return 1
    _release_right=$(release_version "$2") || return 1

    case "$_release_left" in
        *-*) _release_lb=${_release_left#*-}; _release_left=${_release_left%%-*} ;;
        *)   _release_lb=0 ;;
    esac
    case "$_release_right" in
        *-*) _release_rb=${_release_right#*-}; _release_right=${_release_right%%-*} ;;
        *)   _release_rb=0 ;;
    esac

    _release_old_ifs=$IFS
    IFS=.
    set -- $_release_left
    _release_l1=$1 _release_l2=$2 _release_l3=$3
    set -- $_release_right
    _release_r1=$1 _release_r2=$2 _release_r3=$3
    IFS=$_release_old_ifs

    _release_l1=$(release_number "$_release_l1")
    _release_l2=$(release_number "$_release_l2")
    _release_l3=$(release_number "$_release_l3")
    _release_lb=$(release_number "$_release_lb")
    _release_r1=$(release_number "$_release_r1")
    _release_r2=$(release_number "$_release_r2")
    _release_r3=$(release_number "$_release_r3")
    _release_rb=$(release_number "$_release_rb")

    [ "$_release_l1" -gt "$_release_r1" ] && return 0
    [ "$_release_l1" -lt "$_release_r1" ] && return 1
    [ "$_release_l2" -gt "$_release_r2" ] && return 0
    [ "$_release_l2" -lt "$_release_r2" ] && return 1
    [ "$_release_l3" -gt "$_release_r3" ] && return 0
    [ "$_release_l3" -lt "$_release_r3" ] && return 1
    [ "$_release_lb" -gt "$_release_rb" ]
}

release_cache_read() {
    [ -r "$RELEASE_OK_CACHE" ] || return 1
    _release_cache=$(sed -n '1p' "$RELEASE_OK_CACHE")
    case "$_release_cache" in
        *'|'*)
            _release_cached_at=${_release_cache%%|*}
            _release_cached_version=${_release_cache#*|}
            ;;
        *) return 1 ;;
    esac
    case "$_release_cached_at" in ''|*[!0-9]*) return 1 ;; esac
    _release_cached_version=$(release_version "$_release_cached_version") || return 1
    return 0
}

release_cache_fresh() {
    release_cache_read || return 1
    [ "$1" -ge "$_release_cached_at" ] || return 1
    [ $(( $1 - _release_cached_at )) -lt "$RELEASE_OK_TTL" ]
}

release_cache_write() {
    mkdir -p "$RELEASE_VAR" 2>/dev/null || return 1
    _release_tmp="${RELEASE_OK_CACHE}.$$"
    printf '%s|%s\n' "$1" "$2" > "$_release_tmp" || {
        rm -f "$_release_tmp"
        return 1
    }
    release_own "$_release_tmp"
    mv -f "$_release_tmp" "$RELEASE_OK_CACHE"
}

release_fail_recent() {
    [ -r "$RELEASE_FAIL_CACHE" ] || return 1
    _release_failed_at=$(sed -n '1p' "$RELEASE_FAIL_CACHE")
    case "$_release_failed_at" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -ge "$_release_failed_at" ] || return 1
    [ $(( $1 - _release_failed_at )) -lt "$RELEASE_FAIL_TTL" ]
}

release_fail_write() {
    mkdir -p "$RELEASE_VAR" 2>/dev/null || return 0
    _release_tmp="${RELEASE_FAIL_CACHE}.$$"
    printf '%s\n' "$1" > "$_release_tmp" || return 0
    release_own "$_release_tmp"
    mv -f "$_release_tmp" "$RELEASE_FAIL_CACHE"
}

release_lock_acquire() {
    mkdir -p "$RELEASE_VAR" 2>/dev/null || return 1
    _release_lock_mode=""
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$RELEASE_LOCK" || return 1
        if flock -n 9 2>/dev/null; then
            _release_lock_mode="flock"
            return 0
        fi
        exec 9>&-
        return 1
    fi
    if mkdir "${RELEASE_LOCK}.d" 2>/dev/null; then
        _release_lock_mode="mkdir"
        return 0
    fi
    return 1
}

release_lock_release() {
    case "$_release_lock_mode" in
        flock)
            flock -u 9 2>/dev/null || true
            exec 9>&-
            ;;
        mkdir)
            rmdir "${RELEASE_LOCK}.d" 2>/dev/null || true
            ;;
    esac
    _release_lock_mode=""
}

release_fetch_latest() {
    _release_response=$(curl --fail --silent --show-error \
        --connect-timeout 5 --max-time 10 \
        --header "Accept: application/vnd.github+json" \
        --header "User-Agent: IKEv2VPN-release-check" \
        "$RELEASE_API_URL" 2>/dev/null)
    # The response is not reliably line-oriented: asking for
    # application/vnd.github+json gets the whole object on a single line, while
    # the default Accept gets it pretty-printed. Split on commas first so the
    # field can be matched the same way either way.
    _release_tag=$(printf '%s\n' "$_release_response" | tr ',' '\n' |
        sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)
    release_version "$_release_tag"
}

# release_latest - the newest published version, from cache or from GitHub.
#
# Sets RELEASE_LATEST and returns 0 when there is an answer to give; returns 1
# when there is none, which is a different thing from "no update" and is what
# keeps the page quiet rather than claiming the installed version is current.
release_latest() {
    RELEASE_LATEST=""
    _release_now=$(date +%s 2>/dev/null)
    case "$_release_now" in ''|*[!0-9]*) return 1 ;; esac

    if release_cache_fresh "$_release_now"; then
        RELEASE_LATEST=$_release_cached_version
        return 0
    fi

    # A lookup that just failed is not retried on every visit; the last good
    # answer is used meanwhile.
    if release_fail_recent "$_release_now"; then
        release_cache_read && RELEASE_LATEST=$_release_cached_version
        [ -n "$RELEASE_LATEST" ]
        return
    fi

    if release_lock_acquire; then
        # Someone else may have refreshed it while the lock was being taken.
        if release_cache_fresh "$_release_now"; then
            RELEASE_LATEST=$_release_cached_version
            release_lock_release
            return 0
        fi
        _release_tag=$(release_fetch_latest)
        if [ -n "$_release_tag" ]; then
            release_cache_write "$_release_now" "$_release_tag" || true
            rm -f "$RELEASE_FAIL_CACHE"
            RELEASE_LATEST=$_release_tag
        else
            release_fail_write "$_release_now"
            release_cache_read && RELEASE_LATEST=$_release_cached_version
        fi
        release_lock_release
    else
        release_cache_read && RELEASE_LATEST=$_release_cached_version
    fi

    [ -n "$RELEASE_LATEST" ]
}
