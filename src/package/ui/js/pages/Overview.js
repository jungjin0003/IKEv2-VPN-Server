// Overview.js - service state at a glance: stats, the four servers, host info.

import { html } from "../preact.js";
import { t } from "../i18n.js";
import { esc } from "../util.js";
import { SERVER_DEFS, SERVER_KEYS } from "../servers.js";
import { IconServerRow } from "../components/Icons.js";

function Stat({ bg, color, glyph, label, sub, children }) {
    return html`
        <div class="stat">
            <div class="top">
                <span class="ic" style=${"background:" + bg + ";color:" + color}
                      dangerouslySetInnerHTML=${{ __html: glyph }}></span>
                <span>${label}</span>
            </div>
            <div class="val">${children}</div>
            <div class="sub">${sub}</div>
        </div>`;
}

function ServerRow({ m, state, onGo }) {
    const def = SERVER_DEFS[m];
    const on = state[def.enField] === "yes";
    const conn = parseInt(state[def.connKey] || "0", 10) || 0;
    return html`
        <div class="trow" style="grid-template-columns:1.5fr 1fr 1.4fr .9fr;cursor:pointer"
             onClick=${function () { onGo(m); }}>
            <div style="display:flex;align-items:center;gap:10px">
                <span style=${"width:32px;height:32px;border-radius:8px;background:"
                        + (on ? "var(--accent-bg)" : "#f2f4f6")
                        + ";display:flex;align-items:center;justify-content:center;flex:none"}>
                    ${IconServerRow(on ? "var(--accent)" : "#a7aeb4")}
                </span>
                <span style="font-weight:600">${def.title}</span>
            </div>
            <div>
                <span class="badge2" style=${"background:" + (on ? "var(--ok-bg)" : "#f2f4f6")
                        + ";color:" + (on ? "var(--ok)" : "var(--sub)")}>
                    <span class="d" style=${"background:" + (on ? "var(--ok)" : "var(--sub)")}></span>
                    ${on ? t("state_on") : t("state_off")}
                </span>
            </div>
            <div style="color:#5b636b">${on ? (state[def.subnetField] || "-") : "-"}</div>
            <div style="text-align:right;font-weight:600">${on ? conn : "-"}</div>
        </div>`;
}

export function Overview({ state, onGo, onEnable, onDisable }) {
    const s = state || {};
    let activeCount = 0, totalConn = 0;
    SERVER_KEYS.forEach(function (m) {
        if (s[SERVER_DEFS[m].enField] === "yes") activeCount++;
        totalConn += parseInt(s[SERVER_DEFS[m].connKey] || "0", 10) || 0;
    });

    const showSetup = s.priv === "none";
    const showDaemon = s.enabled === "yes" && s.charon !== "yes";

    return html`
        <div class="page">
            <h1>${t("ov_title")}</h1>
            <div class="desc">${t("ov_desc")}</div>

            <div class=${"notice" + (showSetup ? " show" : "")}
                 dangerouslySetInnerHTML=${{ __html: showSetup ? t("setup_notice", { cmd: esc(s.setup_cmd || "") }) : "" }}></div>
            <div class=${"notice" + (showDaemon ? " show" : "")}
                 dangerouslySetInnerHTML=${{ __html: showDaemon ? t("daemon_notice") : "" }}></div>

            <div style="margin-bottom:18px">
                <!-- both stay enabled until the first status arrives, as before -->
                <button class="btn primary" disabled=${!!state && s.enabled === "yes"}
                        onClick=${onEnable}>${t("btn_enable")}</button>${" "}
                <button class="btn" disabled=${!!state && s.enabled !== "yes"}
                        onClick=${onDisable}>${t("btn_disable")}</button>
            </div>

            <div class="statgrid">
                <${Stat} bg="var(--accent-bg)" color="var(--accent)" glyph="&#128421;"
                         label=${t("stat_active")} sub=${t("stat_active_sub")}>
                    ${activeCount}<span class="unit">/ 4</span>
                <//>
                <${Stat} bg="var(--ok-bg)" color="var(--ok)" glyph="&#128279;"
                         label=${t("stat_conn")} sub=${t("stat_conn_sub")}>
                    ${String(s.connections || totalConn || 0)}
                <//>
                <${Stat} bg="#fdf1e7" color="#d97a3a" glyph="&#128196;"
                         label=${t("stat_certs")} sub=${t("stat_certs_sub")}>
                    ${String(s.certs || 0)}
                <//>
                <${Stat} bg="#f0ecfb" color="#7159c4" glyph="&#128100;"
                         label=${t("stat_users")} sub=${t("stat_users_sub")}>
                    ${String(s.dsm_accounts || 0)}
                <//>
            </div>

            <div style="display:grid;grid-template-columns:1.5fr 1fr;gap:16px;align-items:start">
                <div class="card">
                    <div class="chd">
                        <h2>${t("ov_serverstate")}</h2>
                        <span style="font-size:12px;color:var(--sub)">${t("enabled_count", { n: activeCount })}</span>
                    </div>
                    <div class="thead" style="grid-template-columns:1.5fr 1fr 1.4fr .9fr">
                        <div>${t("th_server")}</div><div>${t("th_status")}</div>
                        <div>${t("th_subnet")}</div>
                        <div style="text-align:right">${t("th_conn")}</div>
                    </div>
                    <div>
                        ${SERVER_KEYS.map(function (m) {
                            return html`<${ServerRow} key=${m} m=${m} state=${s} onGo=${onGo} />`;
                        })}
                    </div>
                </div>
                <div class="card"><div class="pad">
                    <h2 style="margin-bottom:14px">${t("ov_serverinfo")}</h2>
                    <div style="display:grid;grid-template-columns:auto 1fr;row-gap:11px;column-gap:14px;font-size:12.5px">
                        <span style="color:var(--sub)">${t("info_addr")}</span>
                        <span style="text-align:right;font-weight:600">${s.hostname || s.cert_cn || "-"}</span>
                        <span style="color:var(--sub)">${t("info_iface")}</span>
                        <span style="text-align:right;font-weight:600">
                            ${s.iface_name ? (s.iface_name + (s.iface_ip ? " (" + s.iface_ip + ")" : "")) : t("iface_none")}
                        </span>
                        <span style="color:var(--sub)">${t("info_port")}</span>
                        <span style="text-align:right;font-weight:600">UDP 500, 4500</span>
                        <span style="color:var(--sub)">${t("info_applied")}</span>
                        <span style="text-align:right;font-weight:600">${s.last_applied || "-"}</span>
                    </div>
                </div></div>
            </div>
        </div>`;
}
