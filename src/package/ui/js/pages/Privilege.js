// Privilege.js - which DSM accounts may log in over IKEv2.

import { html, useState, useEffect } from "../preact.js";
import { t } from "../i18n.js";
import { getJSON, postBusy } from "../api.js";
import { toast } from "../store.js";
import { IconSearch } from "../components/Icons.js";

const COLS = "grid-template-columns:1.6fr 1fr .8fr";

// The page used to live in the DOM permanently, so a typed search term survived
// leaving and coming back. Components unmount now, so it is kept here instead.
let lastQuery = "";

export function Privilege({ onRefresh }) {
    const [users, setUsers] = useState(null);
    // live edit map name -> bool, i.e. the checkbox state before applying
    const [allow, setAllow] = useState({});
    const [query, setQueryState] = useState(lastQuery);
    const [applying, setApplying] = useState(false);

    function setQuery(v) { lastQuery = v; setQueryState(v); }

    function load() {
        setUsers(null);
        getJSON("dsmusers").then(function (list) {
            const l = Array.isArray(list) ? list : [];
            const map = {};
            l.forEach(function (u) { map[u.name] = (u.allowed === "yes"); });
            setUsers(l);
            setAllow(map);
        }, function () { setUsers(false); });
    }

    useEffect(load, []);

    function apply() {
        const allowed = [];
        (users || []).forEach(function (u) {
            if (u.status === "normal" && allow[u.name]) allowed.push(u.name);
        });
        setApplying(true);
        postBusy({ action: "vpnperm", users: allowed.join(",") }).then(function (r) {
            setApplying(false);
            if (!r.success) { toast(r.error || t("fail")); return; }
            toast(t("priv_applied"));
            load();
            onRefresh();
        }).catch(function () { setApplying(false); toast(t("api_failed")); });
    }

    let body;
    if (users === null) {
        body = html`<div class="empty">${t("loading")}</div>`;
    } else if (users === false) {
        body = html`<div class="empty">${t("load_failed")}</div>`;
    } else if (!users.length) {
        body = html`<div class="empty">${t("no_dsm_accounts")}</div>`;
    } else {
        const q = query.toLowerCase();
        const shown = users.filter(function (u) {
            return !q || u.name.toLowerCase().indexOf(q) !== -1;
        });
        if (!shown.length) {
            body = html`<div class="empty">${t("no_search_results")}</div>`;
        } else {
            body = shown.map(function (u) {
                const normal = u.status === "normal";
                return html`
                    <div class="trow" style=${COLS} key=${u.name}>
                        <div style="font-weight:600">${u.name}</div>
                        <div style=${"color:" + (normal ? "var(--ok)" : "#9aa2a8")}>
                            ${normal ? t("st_normal") : t("st_disabled")}
                        </div>
                        <div style="text-align:center">
                            <input type="checkbox" checked=${!!allow[u.name]} disabled=${!normal}
                                   style="width:15px;height:15px;accent-color:var(--accent);margin:0;cursor:pointer"
                                   onChange=${function (e) {
                                       setAllow(Object.assign({}, allow, { [u.name]: e.target.checked }));
                                   }} />
                        </div>
                    </div>`;
            });
        }
    }

    return html`
        <div class="page">
            <h1>${t("priv_title")}</h1>
            <div class="desc">${t("priv_desc")}</div>
            <div class="card" style="max-width:560px">
                <div class="toolbar">
                    <div class="searchbox" style="margin-left:auto">
                        <${IconSearch} />
                        <input placeholder=${t("ph_search")} value=${query}
                               onInput=${function (e) { setQuery(e.target.value); }} />
                    </div>
                </div>
                <div class="thead" style=${COLS}>
                    <div>${t("th_username")}</div><div>${t("th_status")}</div>
                    <div style="text-align:center">IKEv2</div>
                </div>
                <div>${body}</div>
            </div>
            <div class="actions" style="max-width:560px">
                <button class="btn" onClick=${load}>${t("btn_reset")}</button>
                <button class="btn primary" disabled=${applying}
                        onClick=${apply}>${t("btn_apply")}</button>
            </div>
        </div>`;
}
