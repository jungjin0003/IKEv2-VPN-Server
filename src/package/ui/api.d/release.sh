# release.sh - the update notice on the Overview page.
#
# The lookup itself lives in bin/lib/release.sh, shared with the watcher, so
# opening the page reads whatever answer is already cached rather than making
# a request of its own. Raising the DSM notification is the watcher's job and
# is not done here: this runs as the package user and the notification needs
# root, and the page is showing the notice anyway.

. "${TARGET}/bin/lib/release.sh"

do_release() {
    json_headers

    _release_current=$(release_current_version) || {
        printf '{"success":true,"checked":false,"available":false}'
        return
    }

    # "not checked" is kept apart from "no update": a lookup that could not be
    # made says nothing about whether the installed version is current, and the
    # page leaves itself alone rather than claiming it is.
    release_latest || {
        printf '{"success":true,"checked":false,"available":false}'
        return
    }

    if release_is_newer "$RELEASE_LATEST" "$_release_current"; then
        printf '{"success":true,"checked":true,"available":true,"current":"%s","latest":"%s"}' \
            "$_release_current" "$RELEASE_LATEST"
    else
        printf '{"success":true,"checked":true,"available":false,"current":"%s","latest":"%s"}' \
            "$_release_current" "$RELEASE_LATEST"
    fi
}
