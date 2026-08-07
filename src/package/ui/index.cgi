#!/bin/sh
# index.cgi - the management page, behind the DSM session check.
#
# This is what ui/config launches. The page itself is www/index.html, which
# sits outside the directory DSM symlinks into its web root and so cannot be
# fetched directly - reaching it means passing the check below.
#
# DSM launches us without a SynoToken, and with cross-site request forgery
# protection switched on the session cannot be checked without one, so the
# first request is answered with a bootstrap page instead. It carries no data:
# its whole job is to read the token out of the DSM desktop that framed us, put
# it in a cookie and come back. Every request after that has the token, module
# imports included, because the browser attaches a cookie to all of them.

PKG="IKEv2VPN"
TARGET="/var/packages/${PKG}/target"
PAGE="${TARGET}/www/index.html"

. "${TARGET}/lib/auth.sh"

# The bootstrap page. No data, no secrets - it is safe to hand to anyone,
# because everything it can go on to fetch is checked in its own right.
serve_bootstrap() {
    printf 'Content-Type: text/html; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf 'X-Content-Type-Options: nosniff\r\n'
    printf 'X-Frame-Options: SAMEORIGIN\r\n'
    [ -n "$1" ] && web_clear_token_cookie
    printf '\r\n'
    cat <<HTML
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>IKEv2 VPN Server</title>
<style>
body{margin:0;font:13px "Segoe UI",system-ui,sans-serif;color:#2b3138;background:#eef1f4}
.b{max-width:34em;margin:14vh auto;padding:22px 26px;background:#fff;border-radius:8px;
   border:1px solid #e6eaee}
h1{margin:0 0 10px;font-size:15px}p{margin:0 0 10px;line-height:1.6;color:#6d757d}
a{color:#1f6fb2}code{font-size:12px;color:#8b939b}
</style></head>
<body><div class="b" id="m" hidden>
<h1>Open this page from the DSM desktop</h1>
<p>The session could not be established. Sign in to DSM and start
<b>IKEv2 VPN Server</b> from the desktop rather than opening this address
directly.</p>
<p><a href="${SYNO_LOGIN}">Go to DSM</a></p>
<p><code id="d"></code></p>
</div>
<script>
(function () {
    var tried = [];

    function stop(why) {
        document.getElementById("d").textContent = why + " [" + tried.join(" ") + "]";
        document.getElementById("m").hidden = false;
    }

    function go(tok) {
        if (!tok || !/^[A-Za-z0-9._-]{1,64}\$/.test(String(tok))) { stop("no token"); return; }
        sessionStorage.setItem("ikev2_boot", String(Date.now()));
        document.cookie = "${TOKEN_COOKIE}=" + tok + "; Path=${COOKIE_PATH}; SameSite=Strict"
            + (location.protocol === "https:" ? "; Secure" : "");
        location.replace("index.cgi");
    }

    // DSM opens a third-party package by navigating the whole window, not by
    // framing it, so there is usually no parent to ask. login.cgi answers the
    // session it is already carrying: given the cookie and nothing else it
    // returns that session's SynoToken, which is exactly what is needed and
    // needs no window relationship at all.
    function fromWindows() {
        var rels = [];
        try { if (window.parent && window.parent !== window) rels.push([window.parent, "parent"]); }
        catch (e) { tried.push("parent:" + e.name); }
        try { if (window.opener) rels.push([window.opener, "opener"]); }
        catch (e) { tried.push("opener:" + e.name); }
        if (!rels.length) { tried.push("not-framed"); return ""; }

        for (var i = 0; i < rels.length; i++) {
            var w = rels[i][0], tag = rels[i][1];
            // SYNO.SDS.Session.SynoToken is a property, not a getter -
            // dsm.common.bundle.js assigns it on login and reads it back the
            // same way - and _S("SynoToken") is the accessor beside it.
            var list = [
                [tag + ".Session", function () { return w.SYNO.SDS.Session.SynoToken; }],
                [tag + "._S", function () { return w._S("SynoToken"); }]
            ];
            for (var j = 0; j < list.length; j++) {
                try {
                    var t = list[j][1]();
                    if (t) return String(t);
                    tried.push(list[j][0] + ":empty");
                } catch (e) { tried.push(list[j][0] + ":" + e.name); }
            }
        }
        return "";
    }

    // One bootstrap per visit: if we were here moments ago the token we found
    // is not being accepted, and reloading again would only spin.
    var last = +(sessionStorage.getItem("ikev2_boot") || 0);
    if (Date.now() - last < 10000) { stop("token refused"); return; }

    fetch("/webman/login.cgi", { credentials: "same-origin", cache: "no-store" })
        .then(function (r) { return r.json(); })
        .then(function (j) {
            var t = j && j.SynoToken;
            if (t) return go(t);
            tried.push("login.cgi:empty");
            go(fromWindows());
        })
        .catch(function (e) {
            tried.push("login.cgi:" + (e && e.name ? e.name : "failed"));
            go(fromWindows());
        });
})();
</script></body></html>
HTML
    exit 0
}

web_authenticate
RC=$?

case "$RC" in
    0) ;;
    2)
        # A session, but not an administrator's. Not a redirect: DSM would log
        # them straight back in, relaunch the app and land here once more.
        printf 'Status: 403 Forbidden\r\n'
        printf 'Content-Type: text/plain; charset=utf-8\r\n'
        printf 'Cache-Control: no-store\r\n\r\n'
        printf 'This page is available to DSM administrators only.\n'
        exit 0
        ;;
    3) serve_bootstrap "" ;;
    *) serve_bootstrap "clear" ;;
esac

if [ ! -f "$PAGE" ]; then
    printf 'Status: 500 Internal Server Error\r\n'
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
    printf 'the management page is missing from the package\n'
    exit 0
fi

printf 'Content-Type: text/html; charset=utf-8\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'X-Content-Type-Options: nosniff\r\n'
# The page is framed by the DSM desktop, which is the same origin, and by
# nothing else: without this any site could frame it and drive the controls
# underneath its own.
printf 'X-Frame-Options: SAMEORIGIN\r\n'
# Everything the page loads is its own origin - the modules and the stylesheet
# through res.cgi, the API and the download iframe through api.cgi. Inline
# styles are allowed because the markup sets them; no inline script is used.
printf "Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; object-src 'none'; base-uri 'none'; frame-ancestors 'self'\r\n"
printf '\r\n'
cat "$PAGE"
