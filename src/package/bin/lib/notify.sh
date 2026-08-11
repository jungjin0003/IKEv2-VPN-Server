# notify.sh - the DSM desktop notice that a newer release exists.
#
# synodsmnotify does not take text. It takes a tag, and refuses one that DSM
# does not already know:
#
#   title: 'IKEv2 VPN Server' is neither mail string key nor i18n format.
#
# Registering a tag is what conf/resource's "sysnotify" worker does for a
# Synology-signed package. DSM refuses that worker to anyone else - a package
# declaring it cannot be installed at all - so this registers the tag itself,
# in the two places DSM keeps them: the wording under /var/cache/texts/<pkg>/,
# and the tag in the category and translation tables of the text database
# beside it. Both are needed; with either one missing synodsmnotify fails.
#
# The wording is not written here. It ships with the package under
# notify/<lang>/mails and is copied in unchanged, so what reaches the desktop
# is what is in the repository, in the format DSM's own notifications use.
#
# All of this needs root, which is why it hangs off ikev2ctl rather than the
# install scripts: DSM runs those as the package user.

NOTIFY_PKG="IKEv2VPN"
# Defined so the module also works when sourced by ikev2watch, which does not
# load common.sh.
NOTIFY_TARGET="${TARGET:-/var/packages/${NOTIFY_PKG}/target}"
NOTIFY_VAR="${VAR:-/var/packages/${NOTIFY_PKG}/var}"

NOTIFY_SRC="${NOTIFY_TARGET}/notify"
NOTIFY_CACHE="/var/cache/texts/${NOTIFY_PKG}"
NOTIFY_CATDB="/var/cache/texts/notification_category.db"

NOTIFY_TAG="${NOTIFY_PKG}_ReleaseAvailable"
NOTIFY_APP="SYNO.SDS.${NOTIFY_PKG}.Application"
NOTIFY_BIN="/usr/syno/bin/synodsmnotify"

# What was last announced and when, as "<version> <epoch>". The watcher looks
# many times a day; this is what keeps the notice to one a day rather than one
# per look. A version that has not been announced before goes out immediately.
NOTIFY_STATE="${NOTIFY_VAR}/release-notified"
NOTIFY_LOCK="${NOTIFY_VAR}/release-notified.lock"

# The hour the daily reminder is tied to, on the NAS's own clock. A fixed hour
# rather than a rolling day so the reminder does not drift later every time -
# whatever hour the first notice happened to go out would otherwise become the
# hour it arrives forever.
NOTIFY_HOUR=7

notify_sqlite() {
    for _n_b in /bin/sqlite3 /usr/bin/sqlite3 /usr/syno/bin/sqlite3; do
        [ -x "$_n_b" ] && { echo "$_n_b"; return 0; }
    done
    command -v sqlite3 2>/dev/null
}

# notify_field NAME FILE - one "Name: value" line out of a shipped mails file
notify_field() {
    sed -n "s/^$1:[[:space:]]*//p" "$2" 2>/dev/null | head -n 1
}

notify_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# The languages the package ships wording for, as DSM's own three-letter codes.
notify_langs() {
    for _n_d in "$NOTIFY_SRC"/*; do
        [ -f "${_n_d}/mails" ] && basename "$_n_d"
    done
}

notify_registered() {
    _n_sq=$(notify_sqlite)
    [ -n "$_n_sq" ] && [ -f "$NOTIFY_CATDB" ] || return 1

    _n_langs=$(notify_langs)
    [ -n "$_n_langs" ] || return 1
    for _n_l in $_n_langs; do
        [ -f "${NOTIFY_CACHE}/${_n_l}/mails" ] || return 1
    done

    # The category row makes the tag exist; the translation rows are what the
    # send path resolves it through. A tag with only the first is accepted at
    # registration and then fails at send time, so both are checked.
    _n_c=$("$_n_sq" "$NOTIFY_CATDB" \
        "SELECT COUNT(*) FROM category WHERE tag='${NOTIFY_TAG}';" 2>/dev/null)
    [ "${_n_c:-0}" -gt 0 ] 2>/dev/null || return 1
    _n_t=$("$_n_sq" "$NOTIFY_CATDB" \
        "SELECT COUNT(*) FROM translation WHERE tag='${NOTIFY_TAG}';" 2>/dev/null)
    [ "${_n_t:-0}" -gt 0 ] 2>/dev/null
}

notify_register() {
    [ "$(id -u)" = "0" ] || return 1
    _n_sq=$(notify_sqlite)
    [ -n "$_n_sq" ] && [ -f "$NOTIFY_CATDB" ] || return 1
    _n_langs=$(notify_langs)
    [ -n "$_n_langs" ] || return 1

    for _n_l in $_n_langs; do
        mkdir -p "${NOTIFY_CACHE}/${_n_l}" || return 1
        cp -f "${NOTIFY_SRC}/${_n_l}/mails" "${NOTIFY_CACHE}/${_n_l}/mails" || return 1
        chmod 644 "${NOTIFY_CACHE}/${_n_l}/mails" 2>/dev/null
    done

    # Level comes from the shipped wording so the icon and the row agree.
    _n_level=""
    for _n_l in $_n_langs; do
        _n_level=$(notify_field Level "${NOTIFY_SRC}/${_n_l}/mails")
        [ -n "$_n_level" ] && break
    done
    [ -n "$_n_level" ] || _n_level="NOTIFICATION_INFO"

    # target=desktop and an empty format keep this off the mail path entirely,
    # the shape DSM's own desktop-only notifications use.
    "$_n_sq" "$NOTIFY_CATDB" \
        "INSERT OR REPLACE INTO category
             (tag,appid,format,level,target,source,show_in_GUI)
         VALUES ('${NOTIFY_TAG}','${NOTIFY_APP}','','${_n_level}','desktop','${NOTIFY_PKG}',1);" \
        2>/dev/null || return 1

    # Foreign keys are not enforced by default, so the old rows go explicitly.
    "$_n_sq" "$NOTIFY_CATDB" \
        "DELETE FROM translation WHERE tag='${NOTIFY_TAG}';" 2>/dev/null

    for _n_l in $_n_langs; do
        _n_cat=$(notify_field Category "${NOTIFY_SRC}/${_n_l}/mails")
        _n_title=$(notify_field Title "${NOTIFY_SRC}/${_n_l}/mails")
        [ -n "$_n_title" ] || _n_title=$_n_cat
        "$_n_sq" "$NOTIFY_CATDB" \
            "INSERT INTO translation (tag,language,category,title)
             VALUES ('${NOTIFY_TAG}','${_n_l}','$(notify_quote "$_n_cat")','$(notify_quote "$_n_title")');" \
            2>/dev/null
    done

    # DSM parses the wording once and re-reads it only when this database's
    # timestamp moves - not when the files beside it change. Without this the
    # copy above stays invisible for up to an hour.
    touch "$NOTIFY_CATDB"
}

# Registration lives in /var/cache, which the package does not own and DSM may
# rebuild. Rather than assume it survives, every root-side entry point checks
# and puts it back: a stat and one query when it is already there.
notify_ensure() {
    [ "$(id -u)" = "0" ] || return 0
    notify_registered && return 0
    if notify_register; then
        log "registered the DSM notification tag"
        return 0
    fi
    log "WARN: could not register the DSM notification tag"
    return 1
}

notify_unregister() {
    [ "$(id -u)" = "0" ] || return 1
    rm -rf "$NOTIFY_CACHE"
    _n_sq=$(notify_sqlite)
    if [ -n "$_n_sq" ] && [ -f "$NOTIFY_CATDB" ]; then
        "$_n_sq" "$NOTIFY_CATDB" \
            "DELETE FROM translation WHERE tag='${NOTIFY_TAG}';
             DELETE FROM category WHERE tag='${NOTIFY_TAG}';" 2>/dev/null
        touch "$NOTIFY_CATDB"
    fi
    rm -f "$NOTIFY_STATE"
    return 0
}

notify_valid_version() {
    case "$1" in
        ''|*[!0-9.-]*) return 1 ;;
    esac
    printf '%s\n' "$1" |
        grep -Eq '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}(-[0-9]{1,9})?$'
}

# notify_int <value> - a two-digit clock field as a number.
#
# "08" and "09" are not octal here, and an empty field is midnight.
notify_int() {
    _n_i=${1#0}
    case "$_n_i" in ''|*[!0-9]*) _n_i=0 ;; esac
    printf '%s\n' "$_n_i"
}

# notify_reminder_since - the last NOTIFY_HOUR o'clock that has gone by.
#
# Derived from the wall clock rather than counted back from now, so the answer
# follows the NAS's own timezone without this having to know what it is.
notify_reminder_since() {
    _n_h=$(notify_int "$(date +%H 2>/dev/null)")
    _n_m=$(notify_int "$(date +%M 2>/dev/null)")
    _n_s=$(notify_int "$(date +%S 2>/dev/null)")
    _n_midnight=$(( $1 - (_n_h * 3600 + _n_m * 60 + _n_s) ))
    _n_mark=$(( _n_midnight + NOTIFY_HOUR * 3600 ))
    # Before it has come round today, the one that counts is yesterday's.
    [ "$1" -lt "$_n_mark" ] && _n_mark=$(( _n_mark - 86400 ))
    printf '%s\n' "$_n_mark"
}

# notify_due <version> <now> - should this version be announced now?
#
# A version not announced before is due whenever it is found, so a release does
# not sit unmentioned until morning. One already announced is due again at the
# next NOTIFY_HOUR, which is what turns an ignored update into a daily reminder
# that arrives at the same time every day.
notify_due() {
    [ -r "$NOTIFY_STATE" ] || return 0
    _n_seen=$(sed -n '1p' "$NOTIFY_STATE")
    _n_seen_ver=${_n_seen%% *}
    _n_seen_at=${_n_seen##* }
    [ "$_n_seen_ver" = "$1" ] || return 0
    case "$_n_seen_at" in ''|*[!0-9]*) return 0 ;; esac
    [ "$_n_seen_at" -le "$2" ] || return 0
    [ "$_n_seen_at" -lt "$(notify_reminder_since "$2")" ]
}

# do_notify_release <latest> - tell administrators, at most once a day.
do_notify_release() {
    _n_latest="$1"
    notify_valid_version "$_n_latest" || return 2
    [ -x "$NOTIFY_BIN" ] || return 0
    _n_now=$(date +%s 2>/dev/null)
    case "$_n_now" in ''|*[!0-9]*) return 0 ;; esac
    notify_ensure || return 1
    mkdir -p "$NOTIFY_VAR" 2>/dev/null || return 0

    exec 9>"$NOTIFY_LOCK" || return 0
    if command -v flock >/dev/null 2>&1 && ! flock -n 9 2>/dev/null; then
        exec 9>&-
        return 0
    fi

    if ! notify_due "$_n_latest" "$_n_now"; then
        flock -u 9 2>/dev/null || true
        exec 9>&-
        return 0
    fi

    # -e false leaves the wording unescaped, which is what makes the link in it
    # a link rather than visible markup. The version is the only value put into
    # it, and notify_valid_version has already reduced that to digits, dots and
    # one dash, so there is nothing in it to close a tag with.
    "$NOTIFY_BIN" -e false -c "$NOTIFY_APP" @administrators \
        "$NOTIFY_TAG" "{\"%LATEST%\":\"${_n_latest}\"}" >/dev/null 2>&1 || {
        flock -u 9 2>/dev/null || true
        exec 9>&-
        return 1
    }

    _n_tmp="${NOTIFY_STATE}.$$"
    (umask 077; printf '%s %s\n' "$_n_latest" "$_n_now" > "$_n_tmp") &&
        mv -f "$_n_tmp" "$NOTIFY_STATE"
    _n_rc=$?
    [ -f "$_n_tmp" ] && rm -f "$_n_tmp"
    flock -u 9 2>/dev/null || true
    exec 9>&-
    return "$_n_rc"
}
