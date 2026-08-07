# daemon.sh - the bundled charon daemon and the swanctl client that drives it.

swanctl() {
    # swanctl also loads the main strongswan.conf (e.g. for the vici socket
    # path) - without STRONGSWAN_CONF it falls back to the path baked in at
    # ./configure time on the machine that built the binary, which doesn't
    # exist here, and it aborts ("no files found matching ... abort
    # initialization due to invalid configuration").
    STRONGSWAN_CONF="$STRONGSWAN_CONF_OUT" SWANCTL_DIR="$SWANCTL_ETC" "$SWANCTL_BIN" "$@"
}

# pids of every running instance of OUR bundled charon (matched by exe
# path so we never touch a charon belonging to some other package, and
# never miss one just because the pidfile is stale/missing). Prints
# newline-separated pids, empty if none.
#
# NB: /var/packages/<pkg>/target is a symlink to /volume1/@appstore/<pkg>,
# so /proc/<pid>/exe always resolves to the @appstore real path, never the
# symlinked $CHARON_BIN. Compare against the fully-resolved path.
our_charon_pids() {
    REAL_CHARON=$(readlink -f "$CHARON_BIN" 2>/dev/null)
    [ -n "$REAL_CHARON" ] || REAL_CHARON="$CHARON_BIN"
    RESULT=""
    for pd in /proc/[0-9]*; do
        pid=${pd#/proc/}
        exe=$(readlink "${pd}/exe" 2>/dev/null)
        # /proc/<pid>/exe of a deleted/replaced binary may have a
        # " (deleted)" suffix - strip it before comparing
        exe=${exe% (deleted)}
        [ "$exe" = "$REAL_CHARON" ] && RESULT="${RESULT}${pid}
"
    done
    printf '%s' "$RESULT" | grep -v '^$'
}

charon_running() {
    [ -n "$(our_charon_pids)" ]
}

# terminate EVERY running instance of our charon (not just the pidfile
# one). Idempotent, and the primary guard against stacking duplicate
# daemons - which previously could exhaust memory and take the NAS down.
stop_charon() {
    PIDS=$(our_charon_pids)
    if [ -n "$PIDS" ]; then
        for p in $PIDS; do kill "$p" 2>/dev/null; done
        I=0
        while [ -n "$(our_charon_pids)" ] && [ $I -lt 6 ]; do sleep 1; I=$((I + 1)); done
        for p in $(our_charon_pids); do kill -9 "$p" 2>/dev/null; done
    fi
    rm -f "$CHARON_PID" "$CHARON_VICI"
    [ -n "$PIDS" ] && log "charon stopped (pids: $(echo $PIDS | tr '\n' ' '))"
    return 0
}

start_charon() {
    [ -x "$CHARON_BIN" ] || fail "bundled charon binary not found (${CHARON_BIN})"
    # ALWAYS clear any existing instance first so we can never end up with
    # two charons fighting over UDP 500/4500 (the losing one fails to bind
    # but lingers, and repeated applies pile them up).
    stop_charon
    mkdir -p "$VAR"
    rm -f "$CHARON_VICI"
    STRONGSWAN_CONF="$STRONGSWAN_CONF_OUT" SWANCTL_DIR="$SWANCTL_ETC" \
        nohup "$CHARON_BIN" >> "${VAR}/charon.stdout.log" 2>&1 &
    echo $! > "$CHARON_PID"
    # wait briefly for the vici socket to appear (whole-second sleep only -
    # busybox sh on some DSM builds lacks fractional sleep support)
    I=0
    while [ ! -S "$CHARON_VICI" ] && [ $I -lt 8 ]; do sleep 1; I=$((I + 1)); done
    if [ ! -S "$CHARON_VICI" ]; then
        log "WARN: charon started (pid $(cat "$CHARON_PID" 2>/dev/null)) but vici socket did not appear within 8s"
    else
        log "charon started (pid $(cat "$CHARON_PID" 2>/dev/null))"
    fi
}

do_reload() {
    # --load-all already loads pools/credentials/connections/authorities in
    # the right order - no need to also call --load-creds separately.
    charon_running || { start_charon; return 0; }
    OUT=$(swanctl --load-all 2>&1) || { log "WARN: swanctl --load-all failed: $(printf '%s' "$OUT" | tail -n 3)"; return 1; }
    log "swanctl --load-all applied"
}
