// main.js - entry point: status polling, routing and the app shell.

import { html, render, useState, useEffect, useCallback } from "./preact.js";
import { t, LANG } from "./i18n.js";
import { getJSON, postBusy } from "./api.js";
import { toast, showBusy, hideBusy } from "./store.js";
import { SERVER_DEFS } from "./servers.js";
import { TopBar, Sidebar } from "./components/Layout.js";
import { Toast, Busy } from "./components/Overlays.js";
import { ReleasePopup } from "./components/ReleasePopup.js";
import { Overview } from "./pages/Overview.js";
import { Connections } from "./pages/Connections.js";
import { Log } from "./pages/Log.js";
import { General } from "./pages/General.js";
import { Privilege } from "./pages/Privilege.js";
import { Server } from "./pages/Server.js";

const POLL_MS = 15000;

function App() {
    const [state, setState] = useState(null);
    const [release, setRelease] = useState(null);
    const [releaseDismissed, setReleaseDismissed] = useState(false);
    const [page, setPage] = useState("overview");
    // Bumped on every nav click, including a click on the page already shown.
    // It keys the page below, so navigating always remounts and therefore
    // always refetches - the old imperative router reloaded unconditionally too,
    // and the privileges page has no other refresh control.
    const [navSeq, setNavSeq] = useState(0);

    const go = useCallback(function (next) {
        setPage(next);
        setNavSeq(function (n) { return n + 1; });
    }, []);

    const refresh = useCallback(function () {
        return getJSON("status").then(function (s) {
            if (!s.success) { toast(t("status_query_failed")); return; }
            setState(s);
        }).catch(function () { toast(t("api_failed")); });
    }, []);

    // Initial load shows the wait overlay; the poll after it stays silent.
    useEffect(function () {
        showBusy(t("loading"));
        refresh().then(hideBusy, hideBusy);
        const id = setInterval(refresh, POLL_MS);
        return function () { clearInterval(id); };
    }, []);

    // This is deliberately separate from status polling: a release check can
    // involve the package host contacting GitHub and should run only once.
    useEffect(function () {
        getJSON("release").then(function (r) {
            setRelease(r);
        }).catch(function () {
            // A failed optional update check must not disturb package control.
        });
    }, []);

    function enable() {
        postBusy({ action: "enable" }, t("svc_starting")).then(function (r) {
            if (!r.success) { toast(r.error || t("enable_failed")); return; }
            toast(t("enabled_ok"));
            refresh();
        }).catch(function () { toast(t("api_failed")); });
    }

    function disable() {
        if (!confirm(t("confirm_disable"))) return;
        postBusy({ action: "disable" }, t("svc_stopping")).then(function () {
            toast(t("disabled_ok"));
            refresh();
        }).catch(function () { toast(t("api_failed")); });
    }

    // top-right button restarts the VPN service (drops connections briefly);
    // the 15s auto-refresh keeps the view current on its own
    function restart() {
        if (!state || state.enabled !== "yes") { toast(t("svc_not_running")); return; }
        if (!confirm(t("confirm_restart"))) return;
        postBusy({ action: "restart" }, t("svc_restarting")).then(function (r) {
            if (!r.success) { toast(r.error || t("fail")); return; }
            toast(t("svc_restarted"));
            refresh();
        }).catch(function () { toast(t("api_failed")); });
    }

    // key= gives every navigation a fresh component, so one method's half-edited
    // form never carries over to the next and each visit reloads its own data
    const key = page + ":" + navSeq;
    let body;
    if (SERVER_DEFS[page]) {
        body = html`<${Server} key=${key} page=${page} state=${state}
                               onGo=${go} onRefresh=${refresh} />`;
    } else if (page === "connections") {
        body = html`<${Connections} key=${key} onRefresh=${refresh} />`;
    } else if (page === "log") {
        body = html`<${Log} key=${key} />`;
    } else if (page === "general") {
        body = html`<${General} key=${key} state=${state} onRefresh=${refresh} />`;
    } else if (page === "privilege") {
        body = html`<${Privilege} key=${key} onRefresh=${refresh} />`;
    } else {
        body = html`<${Overview} key=${key} state=${state} onGo=${go}
                                 onEnable=${enable} onDisable=${disable} />`;
    }

    return html`
        <div class="app">
            <${TopBar} state=${state} onRestart=${restart} />
            <div class="body">
                <${Sidebar} page=${page} onGo=${go} state=${state} />
                <div class="main">${body}</div>
            </div>
        </div>
        <${Toast} />
        <${Busy} />
        <${ReleasePopup} release=${releaseDismissed ? null : release}
                         onClose=${function () { setReleaseDismissed(true); }} />`;
}

document.documentElement.lang = LANG;
document.title = "IKEv2 VPN Server";
render(html`<${App} />`, document.getElementById("app"));
