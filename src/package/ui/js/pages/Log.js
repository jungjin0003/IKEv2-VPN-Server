// Log.js - authentication and disconnect events, newest first.

import { html, useState, useEffect } from "../preact.js";
import { t } from "../i18n.js";
import { API, getJSON, post } from "../api.js";
import { toast } from "../store.js";
import { Dropdown } from "../components/Dropdown.js";

const COLS = "grid-template-columns:1.3fr 1fr 1fr 2fr";

// The page used to live in the DOM permanently, so the chosen filter survived
// leaving and coming back. Components unmount now, so it is kept here instead.
let lastFilter = "";

function eventLabel(e) {
    if (e === "established") return t("ev_established");
    if (e === "auth_fail") return t("ev_authfail");
    if (e === "disconnected") return t("ev_disconnected");
    return e;
}

function eventDot(e) {
    if (e === "established") return "var(--ok)";
    if (e === "auth_fail") return "var(--bad)";
    return "#9aa2a8";
}

export function Log() {
    const [events, setEvents] = useState(null);
    const [filter, setFilterState] = useState(lastFilter);

    function setFilter(v) { lastFilter = v; setFilterState(v); }

    function load() {
        setEvents(null);
        getJSON("events").then(
            function (l) { setEvents(Array.isArray(l) ? l : []); },
            function () { setEvents(false); }
        );
    }

    useEffect(load, []);

    function clearLog() {
        if (!confirm(t("confirm_clearlog"))) return;
        post({ action: "eventsclear" }).then(function () {
            toast(t("cleared_ok"));
            load();
        });
    }

    const filterOptions = [
        { value: "", label: t("opt_all") },
        { value: "MSCHAPv2", label: "IKEv2/IPsec MSCHAPv2" },
        { value: "PSK", label: "IKEv2/IPsec PSK" },
        { value: "RSA", label: "IKEv2/IPsec RSA" },
        { value: "EAP-TLS", label: "IKEv2/IPsec EAP-TLS" }
    ];

    let body;
    if (events === null) {
        body = html`<div class="empty">${t("loading")}</div>`;
    } else if (events === false) {
        body = html`<div class="empty">${t("load_failed")}</div>`;
    } else {
        const shown = events.filter(function (e) { return !filter || e.proto === filter; });
        if (!shown.length) {
            body = html`<div class="empty">${t("no_events")}</div>`;
        } else {
            // newest first
            body = shown.slice().reverse().map(function (e) {
                return html`
                    <div class="trow" style=${COLS} key=${e.time + e.proto + e.ip}>
                        <div style="color:#6b737b;font-variant-numeric:tabular-nums">${e.time}</div>
                        <div style="color:#6b737b">${e.proto}</div>
                        <div>${e.ip || "-"}</div>
                        <div style="display:flex;align-items:center;gap:7px">
                            <span class="dot" style=${"background:" + eventDot(e.event)}></span>
                            ${eventLabel(e.event)}
                        </div>
                    </div>`;
            });
        }
    }

    return html`
        <div class="page">
            <h1>${t("log_title")}</h1>
            <div class="desc">${t("log_desc")}</div>
            <div class="card">
                <div class="toolbar">
                    <button class="btn" onClick=${clearLog}>${t("btn_clear")}</button>
                    <button class="btn"
                            onClick=${function () { window.open(API + "?action=exportlog", "_blank"); }}>
                        ${t("btn_export")}
                    </button>
                    <div style="flex:1"></div>
                    <${Dropdown} value=${filter} options=${filterOptions}
                                 onChange=${setFilter} width="200px" />
                </div>
                <div class="thead" style=${COLS}>
                    <div>${t("th_datetime")}</div><div>${t("th_proto")}</div>
                    <div>${t("th_ip")}</div><div>${t("th_event")}</div>
                </div>
                <div>${body}</div>
            </div>
        </div>`;
}
