// api.js - every call to api.cgi goes through here.

import { showBusy, hideBusy } from "./store.js";

export const API = "api.cgi";

export function post(params) {
    return fetch(API, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams(params).toString()
    }).then(function (r) { return r.json(); });
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
    return fetch(API + "?action=" + action, { cache: "no-store" })
        .then(function (r) { return r.json(); });
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
