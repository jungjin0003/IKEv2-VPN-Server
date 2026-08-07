// General.js - settings shared by every server.

import { html, useState, useEffect } from "../preact.js";
import { t } from "../i18n.js";
import { postBusy } from "../api.js";
import { toast } from "../store.js";
import { isEditing } from "../util.js";
import { Dropdown } from "../components/Dropdown.js";

// "name:ip,name:ip" -> dropdown options, with "all interfaces" first. A stored
// interface that is no longer present (unplugged) is kept visible so applying
// the form does not silently drop it.
function ifaceOptions(state, current) {
    const opts = [{ value: "", label: t("opt_all_ifaces") }];
    let seen = false;
    (state.iface_list || "").split(",").forEach(function (entry) {
        if (!entry) return;
        const p = entry.split(":");
        const nm = p[0];
        const ip = p[1] || "";
        opts.push({ value: nm, label: nm + (ip ? " (" + ip + ")" : "") });
        if (nm === current) seen = true;
    });
    if (current && !seen) opts.push({ value: current, label: current + " " + t("iface_missing") });
    return opts;
}

function formFrom(state) {
    return {
        hostname: state.hostname || "",
        enc: state.enc || "auto",
        iface: state.iface || "",
        autoblock: state.autoblock === "yes"
    };
}

export function General({ state, onRefresh }) {
    const s = state || {};
    const [form, setForm] = useState(function () { return formFrom(s); });

    // Re-seed from the 15s status poll, but never while a field has focus -
    // that would overwrite what is being typed.
    useEffect(function () {
        if (!state || isEditing()) return;
        setForm(formFrom(state));
    }, [state]);

    function set(key, value) {
        setForm(Object.assign({}, form, { [key]: value }));
    }

    function apply() {
        postBusy({
            action: "save", scope: "general",
            hostname: form.hostname.trim(),
            enc: form.enc,
            iface: form.iface,
            autoblock: form.autoblock ? "yes" : "no"
        }).then(function (r) {
            if (!r.success) { toast(r.error || t("fail")); return; }
            toast(t("settings_applied"));
            onRefresh();
        }).catch(function () { toast(t("api_failed")); });
    }

    const encOptions = [
        { value: "auto", label: t("enc_auto_opt") },
        { value: "aes256", label: t("enc_aes256") },
        { value: "aes128", label: t("enc_aes128") }
    ];
    const dsmabOff = s.dsm_autoblock === "no";

    return html`
        <div class="page">
            <h1>${t("gen_title")}</h1>
            <div class="desc">${t("gen_desc")}</div>

            <div class="card"><div class="pad">
                <div class="form-row">
                    <label>${t("lbl_hostname")}</label>
                    <input type="text" placeholder=${t("ph_hostname")} value=${form.hostname}
                           onInput=${function (e) { set("hostname", e.target.value); }} />
                </div>
                <div class="form-row">
                    <label>${t("lbl_enc")}</label>
                    <${Dropdown} value=${form.enc} options=${encOptions}
                                 onChange=${function (v) { set("enc", v); }} />
                </div>
                <div class="form-row">
                    <label>${t("lbl_iface")}</label>
                    <${Dropdown} value=${form.iface} options=${ifaceOptions(s, form.iface)}
                                 onChange=${function (v) { set("iface", v); }} />
                </div>
                <div class="form-row">
                    <label>${t("lbl_egress")}</label>
                    <span style="color:#4a525a">
                        ${s.iface_name ? (s.iface_name + (s.iface_ip ? " (" + s.iface_ip + ")" : "")) : t("iface_none")}
                    </span>
                </div>
            </div></div>

            <div class="card"><div class="pad">
                <h2 style="margin-bottom:12px">${t("sec_title")}</h2>
                <label class="chk">
                    <input type="checkbox" checked=${form.autoblock}
                           onChange=${function (e) { set("autoblock", e.target.checked); }} />
                    <span>${t("autoblock_label")}</span>
                </label>
                <div class=${"notice" + (dsmabOff ? " show" : "")} style="margin-top:10px"
                     dangerouslySetInnerHTML=${{ __html: dsmabOff ? t("dsmab_off") : "" }}></div>
            </div></div>

            <div class="actions">
                <button class="btn"
                        onClick=${function () { setForm(formFrom(s)); }}>${t("btn_reset")}</button>
                <button class="btn primary" onClick=${apply}>${t("btn_apply")}</button>
            </div>
        </div>`;
}
