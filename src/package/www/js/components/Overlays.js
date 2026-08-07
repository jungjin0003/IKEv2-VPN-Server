// Overlays.js - the toast and the busy overlay.
//
// Both are triggered from outside the component tree (api helpers, event
// handlers) through store.js, and rendered once at the app root.

import { html } from "../preact.js";
import { t } from "../i18n.js";
import { toastStore, busyStore } from "../store.js";

export function Toast() {
    const msg = toastStore.use();
    return html`<div id="toast" class=${msg ? "show" : ""}>${msg}</div>`;
}

export function Busy() {
    const busy = busyStore.use();
    return html`
        <div id="busy" class=${busy.show ? "show" : ""}>
            <div class="busy-box">
                <div class="spinner"></div>
                <div class="busy-msg">${busy.msg || t("applying")}</div>
                <div class="busy-sub">${t("applying_sub")}</div>
            </div>
        </div>`;
}
