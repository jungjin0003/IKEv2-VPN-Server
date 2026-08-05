// Server.js - the per-method server page, shared by all four auth methods.
//
// SERVER_DEFS decides which rows appear, so this one component covers
// MSCHAPv2, PSK, RSA and EAP-TLS.

import { html, useState, useEffect } from "../preact.js";
import { t } from "../i18n.js";
import { getJSON, post, postBusy, postDownload } from "../api.js";
import { toast } from "../store.js";
import { isEditing } from "../util.js";
import { SERVER_DEFS, PROFILE_BUTTONS } from "../servers.js";
import { Dropdown } from "../components/Dropdown.js";
import { IconServerHead } from "../components/Icons.js";

// DSM certificates available to present. Loaded once, then reused by every
// server page; null means "not fetched yet".
let dsmCerts = null;

function formFrom(state, def) {
    const oct = (state[def.subnetField] || "").split("/")[0].split(".");
    // an empty stored DNS means automatic (the NAS's own resolvers)
    const dns = state[def.dnsField] || "";
    return {
        enabled: state[def.enField] === "yes",
        ip1: oct[0] || "", ip2: oct[1] || "", ip3: oct[2] || "",
        dnsManual: dns !== "",
        dns: dns !== "" ? dns : (state.server_dns || ""),
        psk: "",
        cert: def.certField ? (state[def.certField] || "") : ""
    };
}

// Only the DSM certificates are offered. An id that no longer exists in DSM is
// kept visible so saving the form does not silently drop it.
// certs === null means the list has not been fetched yet: show nothing at all,
// rather than briefly claiming DSM has no certificates.
function certOptions(certs, effective) {
    if (certs === null) return [];
    if (!certs.length) return [{ value: "", label: t("cert_none") }];
    const opts = certs.map(function (c) {
        return { value: c.id, label: c.label || c.id };
    });
    if (effective && !certs.some(function (c) { return c.id === effective; })) {
        opts.push({ value: effective, label: effective + " " + t("cert_missing") });
    }
    return opts;
}

// The id this server will actually present. An empty stored value means "use
// whatever DSM defaults to", which is resolved to a concrete id here so that
// saving pins it - otherwise the served certificate would silently follow a
// later change of DSM's default.
function effectiveCertId(certs, stored, state) {
    if (certs === null || !certs.length) return "";
    const eff = stored || (state && state.dsm_cert_default) || "";
    if (eff) return eff;
    return (certs[0] && certs[0].id) || "";
}

function encLabel(v) {
    if (v === "aes256") return t("enc_aes256");
    if (v === "aes128") return t("enc_aes128");
    return t("enc_auto_short");
}

function octet(v) {
    v = v.replace(/[^0-9]/g, "");
    if (v !== "" && parseInt(v, 10) > 255) v = "255";
    return v;
}

function ClientCerts({ certList, onRefresh }) {
    const [list, setList] = useState(certList || []);
    const [name, setName] = useState("");
    const [pass, setPass] = useState("");

    useEffect(function () { setList(certList || []); }, [certList]);

    function reload() {
        getJSON("status").then(function (s) { setList(s.cert_list || []); });
    }

    function issue() {
        if (!name.trim() || !pass) { toast(t("enter_namepass")); return; }
        postDownload({ action: "certissue", user: name.trim(), p12pass: pass });
        // the download is a form POST into a hidden iframe, so there is nothing
        // to await - give the daemon a moment, then pick up the new entry
        setTimeout(function () { reload(); onRefresh(); }, 1500);
    }

    function del(certName) {
        if (!confirm(t("confirm_delcert", { name: certName }))) return;
        post({ action: "certdel", user: certName }).then(function (r) {
            toast(r.success ? t("deleted_ok") : t("fail"));
            reload();
            onRefresh();
        });
    }

    const inputStyle = "height:32px;border:1px solid #c3ccd4;border-radius:6px;padding:0 8px;width:160px";

    return html`
        <div class="card">
            <div class="chd"><h2>${t("clientcert_title")}</h2></div>
            <div class="pad" style="padding-bottom:0">
                <div style="display:flex;gap:8px;margin-bottom:14px">
                    <input type="text" placeholder=${t("ph_certname")} style=${inputStyle}
                           value=${name} onInput=${function (e) { setName(e.target.value); }} />
                    <input type="password" placeholder=${t("ph_p12pass")} style=${inputStyle}
                           value=${pass} onInput=${function (e) { setPass(e.target.value); }} />
                    <button class="btn primary sm" onClick=${issue}>${t("btn_issue")}</button>
                </div>
            </div>
            <div class="thead" style="grid-template-columns:1.6fr 1.4fr .8fr">
                <div>${t("th_name")}</div><div>${t("th_expiry")}</div>
                <div style="text-align:right">${t("th_action")}</div>
            </div>
            <div>
                ${!list.length
                    ? html`<div class="empty">${t("no_certs")}</div>`
                    : list.map(function (c) {
                        return html`
                            <div class="trow" style="grid-template-columns:1.6fr 1.4fr .8fr">
                                <div>${c.name}</div>
                                <div>${c.expires || "-"}</div>
                                <div style="text-align:right">
                                    <button class="btn danger sm"
                                            onClick=${function () { del(c.name); }}>${t("btn_delete")}</button>
                                </div>
                            </div>`;
                    })}
            </div>
        </div>`;
}

export function Server({ page, state, onGo, onRefresh }) {
    const def = SERVER_DEFS[page];
    const s = state || {};
    const [form, setForm] = useState(function () { return formFrom(s, def); });
    const [certs, setCerts] = useState(dsmCerts);

    // Re-seed when the method changes or the poll brings new state, but never
    // while a field has focus.
    useEffect(function () {
        if (!state || isEditing()) return;
        setForm(formFrom(state, def));
    }, [state, page]);

    // DSM certificate list: fetched once, then served from the module cache.
    // The cache is read again here rather than trusted from useState, because a
    // fetch started by a previous mount can resolve between this component's
    // render and its effect - without this the page would keep showing an empty
    // list for the rest of the session.
    useEffect(function () {
        if (!def.cert) return;
        if (dsmCerts !== null) {
            if (certs === null) setCerts(dsmCerts);
            return;
        }
        getJSON("dsmcerts").then(function (list) {
            dsmCerts = Array.isArray(list) ? list : [];
            setCerts(dsmCerts);
        }, function () {
            dsmCerts = [];
            setCerts(dsmCerts);
        });
    }, [page, certs]);

    // Pin the resolved certificate id into the form as soon as the list is
    // known, so that what is saved is exactly what the dropdown shows.
    useEffect(function () {
        if (!def.cert || certs === null) return;
        const eff = effectiveCertId(certs, form.cert, s);
        if (eff !== form.cert) setForm(Object.assign({}, form, { cert: eff }));
    }, [certs, form.cert, s.dsm_cert_default]);

    function set(key, value) {
        setForm(Object.assign({}, form, { [key]: value }));
    }

    function apply() {
        if (form.ip1 === "" || form.ip2 === "" || form.ip3 === "") {
            toast(t("subnet_incomplete"));
            return;
        }
        const params = {
            action: "save", scope: page,
            enabled: form.enabled ? "yes" : "no",
            subnet: form.ip1 + "." + form.ip2 + "." + form.ip3 + ".0/24",
            dns_manual: form.dnsManual ? "yes" : "no",
            dns: form.dnsManual ? form.dns.trim() : ""
        };
        if (def.psk) params.psk = form.psk;
        if (def.cert) params.cert = form.cert;
        postBusy(params).then(function (r) {
            if (!r.success) { toast(r.error || t("fail")); return; }
            toast(t("settings_applied"));
            onRefresh();
        }).catch(function () { toast(t("api_failed")); });
    }

    // form.cert is normalised by the effect above, so display and payload can
    // never disagree: what the dropdown shows is what apply() sends.
    const certOpts = certOptions(certs, form.cert);
    const certValue = effectiveCertId(certs, form.cert, s);

    const profiles = PROFILE_BUTTONS[page] || [];
    const profileLabels = {
        ios: "iOS / macOS", windows: "Windows", android: t("prof_android"),
        ios_psk: "iOS / macOS (PSK)", ca: t("prof_ca")
    };

    const dsmCount = (typeof s.dsm_accounts !== "undefined") ? parseInt(s.dsm_accounts, 10) : NaN;

    return html`
        <div class="page" style="max-width:780px">
            <div style="display:flex;align-items:center;gap:12px;margin-bottom:6px">
                <span style="width:38px;height:38px;border-radius:10px;background:var(--accent-bg);display:flex;align-items:center;justify-content:center;flex:none">
                    <${IconServerHead} />
                </span>
                <div>
                    <div style="font-size:20px;font-weight:700;display:flex;align-items:center;gap:8px">
                        <span>${def.title}</span>
                        ${def.beta && html`<span class="beta-tag">BETA</span>`}
                    </div>
                    <div style="font-size:12.5px;color:var(--sub)">${t("sv_desc")}</div>
                </div>
            </div>

            <div class=${"notice" + (def.beta ? " show" : "")} style="background:#fff6e5;color:#8a5a00"
                 dangerouslySetInnerHTML=${{ __html: def.beta ? t("beta_notice") : "" }}></div>

            <div class="card"><div class="pad">
                <label class="chk" style="padding-bottom:16px;margin-bottom:16px;border-bottom:1px solid var(--line2)">
                    <input type="checkbox" checked=${form.enabled}
                           onChange=${function (e) { set("enabled", e.target.checked); }} />
                    <span style="font-weight:600;font-size:14px">
                        ${t("server_enable_suffix", { title: def.title })}
                    </span>
                </label>

                <div class="form-row">
                    <label>${t("lbl_subnet")}</label>
                    <div class="octets">
                        ${["ip1", "ip2", "ip3"].map(function (k, i) {
                            return html`
                                ${i > 0 && html`<span class="dot-sep">.</span>`}
                                <input type="text" maxlength="3" inputmode="numeric" value=${form[k]}
                                       onInput=${function (e) { set(k, octet(e.target.value)); }} />`;
                        })}
                        <span class="dot-sep">.</span>
                        <span class="octet-suffix">0</span>
                    </div>
                </div>

                <div class="form-row">
                    <label>${t("lbl_dns")}</label>
                    <label class="chk">
                        <input type="checkbox" checked=${form.dnsManual}
                               onChange=${function (e) {
                                   const manual = e.target.checked;
                                   setForm(Object.assign({}, form, {
                                       dnsManual: manual,
                                       dns: manual ? form.dns : (s.server_dns || "")
                                   }));
                               }} />
                        <span>${t("dns_manual")}</span>
                    </label>
                </div>
                <div class="form-row">
                    <label>${t("lbl_dns_addr")}</label>
                    <input type="text" placeholder="8.8.8.8" disabled=${!form.dnsManual} value=${form.dns}
                           onInput=${function (e) { set("dns", e.target.value); }} />
                </div>

                <div class=${"notice" + (def.dsmauth ? " show" : "")}
                     style="background:var(--accent-bg);color:#2b5f86"
                     dangerouslySetInnerHTML=${{ __html: def.dsmauth
                        ? t("dsmauth_notice") + (!isNaN(dsmCount) ? t("dsmauth_count", { n: dsmCount }) : "")
                        : "" }}></div>

                ${def.psk && html`
                    <div class="form-row">
                        <label>${t("lbl_psk")}</label>
                        <input type="password" placeholder=${s.psk ? t("psk_set") : t("ph_psk_auto")}
                               value=${form.psk}
                               onInput=${function (e) { set("psk", e.target.value); }} />
                    </div>`}

                <!-- .form-row is a two-column grid and the link is a sibling
                     of the value, not nested in it, so it lands on a second
                     row. The separator is a non-breaking space on purpose: a
                     plain space is a white-space-only anonymous grid item,
                     which grid does not render, and the link would then shift
                     into the label column. -->
                <div class="form-row">
                    <label>${t("lbl_enc")}</label>
                    <span style="color:#4a525a">${encLabel(s.enc)}</span>
                    ${"\u00a0"}
                    <a href="#" onClick=${function (e) { e.preventDefault(); onGo("general"); }}
                       >${t("enc_change_link")}</a>
                </div>

                ${def.cert && html`
                    <div class="form-row">
                        <label>${t("lbl_servercert")}</label>
                        <${Dropdown} value=${certValue} options=${certOpts}
                                     onChange=${function (v) { set("cert", v); }} />
                    </div>`}

                ${def.clientca && html`
                    <div class="form-row">
                        <label>${t("lbl_clientca")}</label>
                        <span style="color:#4a525a">${s.clientca_cn || t("clientca_notissued")}</span>
                    </div>`}
            </div></div>

            <div class="actions">
                <button class="btn"
                        onClick=${function () { setForm(formFrom(s, def)); }}>${t("btn_reset")}</button>
                <button class="btn primary" onClick=${apply}>${t("btn_apply")}</button>
            </div>

            ${profiles.length > 0 && html`
                <div class="card"><div class="pad">
                    <h2 style="margin-bottom:12px">${t("profiles_title")}</h2>
                    <div style="display:flex;flex-wrap:wrap;gap:8px">
                        ${profiles.map(function (type) {
                            return html`
                                <button class="btn sm"
                                        onClick=${function () { postDownload({ action: "profile", type: type }); }}>
                                    ${profileLabels[type]}
                                </button>`;
                        })}
                    </div>
                </div></div>`}

            ${def.clientca && html`<${ClientCerts} certList=${s.cert_list} onRefresh=${onRefresh} />`}
        </div>`;
}
