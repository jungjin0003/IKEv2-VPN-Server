// ReleasePopup.js - a small non-blocking update notice shown on app entry.

import { html } from "../preact.js";
import { t } from "../i18n.js";

const RELEASE_URL = "https://github.com/jungjin0003/IKEv2-VPN-Server/releases/latest";

export function ReleasePopup({ release, onClose }) {
    if (!release || release.available !== true) return null;

    return html`
        <aside class="release-popup" role="dialog" aria-labelledby="release-popup-title">
            <div class="release-popup-head">
                <strong id="release-popup-title">${t("release_popup_title")}</strong>
                <button class="release-popup-close" type="button"
                        aria-label=${t("release_dismiss")} onClick=${onClose}>x</button>
            </div>
            <div class="release-popup-body">
                ${t("release_available", { version: release.latest })}
            </div>
            <a class="release-popup-link" href=${RELEASE_URL}
               target="_blank" rel="noopener noreferrer">${t("release_view")}</a>
        </aside>`;
}
