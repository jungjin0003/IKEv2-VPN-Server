// api.js - every call to api.cgi goes through here.

import { showBusy, hideBusy } from "./store.js";

export const API = "api.cgi";

// Nothing here carries the session token by hand. index.cgi's bootstrap put it
// in a cookie, so the browser attaches it to everything on this path - these
// requests, the download form's post, and the module imports that fetched this
// file in the first place. A query string would not have survived those
// imports, which resolve relative to the module's own URL.
//
// api.cgi answers 403 and nothing else once the token stops being accepted, so
// reload: index.cgi is the way back in, and it either gets a fresh token or
// says why it cannot.
function check(r) {
    if (r.status === 403) {
        window.location.reload();
        return new Promise(function () { /* never settles; the reload wins */ });
    }
    return r.json();
}

export function post(params) {
    return fetch(API, {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams(params).toString()
    }).then(check);
}

// post that shows the busy overlay for the whole round-trip (used by the
// "apply" buttons, which restart the service). Always clears the overlay.
export function postBusy(params, msg) {
    showBusy(msg);
    return post(params).then(
        function (r) { hideBusy(); return r; },
        function (e) { hideBusy(); throw e; }
    );
}

export function getJSON(action) {
    return fetch(API + "?action=" + action, {
        cache: "no-store",
        credentials: "same-origin"
    }).then(check);
}

// Downloads (client profiles, .p12 certificates) are POSTs whose response is a
// file, so they go through a hidden form targeting a hidden iframe rather than
// fetch - the browser then handles the Content-Disposition itself.
export function postDownload(fields) {
    const f = document.getElementById("f_download");
    f.action = API;
    f.innerHTML = "";
    Object.keys(fields).forEach(function (name) {
        const i = document.createElement("input");
        i.type = "hidden";
        i.name = name;
        i.value = fields[name];
        f.appendChild(i);
    });
    f.submit();
}
