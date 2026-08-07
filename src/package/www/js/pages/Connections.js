// Connections.js - the live IKEv2 sessions, with a per-method disconnect.

import { html, useState, useEffect } from "../preact.js";
import { t } from "../i18n.js";
import { getJSON, post } from "../api.js";
import { toast } from "../store.js";
import { IconNoConnections } from "../components/Icons.js";

const COLS = "grid-template-columns:1.1fr 1.3fr 1.3fr 1fr .9fr";

export function Connections({ onRefresh }) {
    // null = still loading, false = the request failed
    const [list, setList] = useState(null);

    function load() {
        setList(null);
        getJSON("connections").then(
            function (l) { setList(Array.isArray(l) ? l : []); },
            function () { setList(false); }
        );
    }

    useEffect(load, []);

    function disconnect(conn) {
        if (!confirm(t("confirm_disconnect"))) return;
        post({ action: "disconnect", conn: conn }).then(function (r) {
            toast(r.success ? t("disconnected_ok") : t("fail"));
            load();
            onRefresh();
        });
    }

    let body;
    if (list === null) {
        body = html`<div class="empty">${t("loading")}</div>`;
    } else if (list === false) {
        body = html`<div class="empty">${t("load_failed")}</div>`;
    } else if (!list.length) {
        body = html`
            <div class="empty">
                <${IconNoConnections} />
                <div>${t("no_connections")}</div>
            </div>`;
    } else {
        body = list.map(function (c) {
            return html`
                <div class="trow" style=${COLS} key=${c.conn + c.ip}>
                    <div style="font-weight:600">${c.proto}</div>
                    <div>${c.ip || "-"}</div>
                    <div>${c.virtual_ip || "-"}</div>
                    <div>
                        <span class="badge2" style="background:var(--ok-bg);color:var(--ok)">
                            <span class="d" style="background:var(--ok)"></span>${c.state}
                        </span>
                    </div>
                    <div style="text-align:right">
                        <button class="btn danger sm"
                                onClick=${function () { disconnect(c.conn); }}>${t("btn_disconnect")}</button>
                    </div>
                </div>`;
        });
    }

    return html`
        <div class="page">
            <h1>${t("conn_title")}</h1>
            <div class="desc">${t("conn_desc")}</div>
            <div class="card">
                <div class="toolbar">
                    <div style="flex:1"></div>
                    <button class="btn" onClick=${load}>${t("btn_refresh2")}</button>
                </div>
                <div class="thead" style=${COLS}>
                    <div>${t("th_proto")}</div><div>${t("th_clientip")}</div>
                    <div>${t("th_assignedip")}</div><div>${t("th_status")}</div>
                    <div style="text-align:right">${t("th_action")}</div>
                </div>
                <div>${body}</div>
            </div>
        </div>`;
}
