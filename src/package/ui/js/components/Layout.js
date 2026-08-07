// Layout.js - the frame every page sits in: top bar and sidebar.

import { html } from "../preact.js";
import { t } from "../i18n.js";
import { SERVER_DEFS, SERVER_KEYS } from "../servers.js";
import {
    IconLogo, IconRestart, IconOverview, IconConnections,
    IconLog, IconGeneral, IconPrivilege, IconServer
} from "./Icons.js";

const MAIN_NAV = [
    { key: "overview",    icon: IconOverview,    label: "nav_overview" },
    { key: "connections", icon: IconConnections, label: "nav_connections" },
    { key: "log",         icon: IconLog,         label: "nav_log" },
    { key: "general",     icon: IconGeneral,     label: "nav_general" },
    { key: "privilege",   icon: IconPrivilege,   label: "nav_privilege" }
];

function NavItem({ nav, page, onGo, icon, children }) {
    return html`
        <div class=${"navitem" + (page === nav ? " active" : "")}
             data-nav=${nav} onClick=${function () { onGo(nav); }}>
            <${icon} />${children}
        </div>`;
}

function ServerNav({ nav, page, onGo, state }) {
    const on = state && state[SERVER_DEFS[nav].enField] === "yes";
    return html`
        <${NavItem} nav=${nav} page=${page} onGo=${onGo} icon=${IconServer}>
            <span class="nm">${SERVER_DEFS[nav].title}</span>
            <span class="dot" style=${"background:" + (on ? "#54d17a" : "#d3d8dd")}></span>
        <//>`;
}

export function TopBar({ state, onRestart }) {
    const running = state && state.enabled === "yes" && state.charon === "yes";
    let label = "-";
    if (state) {
        label = state.enabled !== "yes"
            ? t("svc_stopped")
            : (state.charon === "yes" ? t("svc_running") : t("svc_daemon_stopped"));
    }
    return html`
        <div class="topbar">
            <${IconLogo} />
            <div class="title">IKEv2 VPN Server</div>
            <div class="spacer"></div>
            <div class="stat">
                <span class=${"dot " + (running ? "ok" : "bad")}></span>
                <span>${label}</span>
            </div>
            <button class="iconbtn" title=${t("restart_title")} onClick=${onRestart}>
                <${IconRestart} />
            </button>
        </div>`;
}

export function Sidebar({ page, onGo, state }) {
    return html`
        <div class="sidebar">
            <div class="hd">${t("nav_service_group")}</div>
            ${MAIN_NAV.map(function (n) {
                return html`
                    <${NavItem} nav=${n.key} page=${page} onGo=${onGo} icon=${n.icon}>
                        <span class="nm">${t(n.label)}</span>
                    <//>`;
            })}
            <div class="hd">${t("nav_server_group")}</div>
            <${ServerNav} nav="mschapv2" page=${page} onGo=${onGo} state=${state} />
            <div class="hd beta">Beta</div>
            ${SERVER_KEYS.slice(1).map(function (k) {
                return html`<${ServerNav} nav=${k} page=${page} onGo=${onGo} state=${state} />`;
            })}
        </div>`;
}
