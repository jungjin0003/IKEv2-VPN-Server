// Dropdown.js - the styled select used across the UI.
//
// Replaces the browser's <select>, which cannot be styled consistently across
// DSM's supported browsers. The popup is position:fixed and carries a high
// z-index, so it is never clipped by the scrolling panes it sits inside; it is
// measured and placed after every open, and flips above the box when there is
// not enough room below.
//
// props: value, options ([{value,label}]), onChange(value), disabled, width

import { html, useState, useRef, useEffect, useLayoutEffect } from "../preact.js";
import { IconChevron } from "./Icons.js";

export function Dropdown({ value, options, onChange, disabled, width }) {
    const [open, setOpen] = useState(false);
    const boxRef = useRef(null);
    const popRef = useRef(null);

    const opts = options || [];
    const selected = opts.filter(function (o) { return o.value === value; })[0];

    // A disabled dropdown must never stay open (the value can be disabled while
    // the popup is showing, e.g. when a checkbox above it is unticked).
    useEffect(function () {
        if (disabled && open) setOpen(false);
    }, [disabled, open]);

    // Position the popup against the box. Runs before paint so it never appears
    // at the wrong place first.
    useLayoutEffect(function () {
        if (!open || !boxRef.current || !popRef.current) return;
        const r = boxRef.current.getBoundingClientRect();
        const pop = popRef.current;
        pop.style.left = r.left + "px";
        pop.style.width = r.width + "px";
        const popH = pop.offsetHeight;
        const below = window.innerHeight - r.bottom;
        pop.style.top = (below < popH + 8 && r.top > below)
            ? (r.top - popH - 4) + "px"
            : (r.bottom + 4) + "px";
    }, [open, opts, value]);

    // Close on an outside click, and on any scroll/resize - the popup is fixed,
    // so it would otherwise stay behind while the box moves away underneath.
    useEffect(function () {
        if (!open) return;
        function onDown(e) {
            if (boxRef.current && boxRef.current.contains(e.target)) return;
            if (popRef.current && popRef.current.contains(e.target)) return;
            setOpen(false);
        }
        function onMove() { setOpen(false); }
        document.addEventListener("mousedown", onDown, true);
        window.addEventListener("scroll", onMove, true);
        window.addEventListener("resize", onMove, true);
        return function () {
            document.removeEventListener("mousedown", onDown, true);
            window.removeEventListener("scroll", onMove, true);
            window.removeEventListener("resize", onMove, true);
        };
    }, [open]);

    const cls = "dd" + (disabled ? " disabled" : "") + (open && !disabled ? " open" : "");

    return html`
        <div class=${cls} style=${width ? "width:" + width : null}>
            <div class="dd-box" ref=${boxRef}
                 onClick=${function () { if (!disabled) setOpen(!open); }}>
                <span class="dd-val">${selected ? selected.label : ""}</span>
                <span class="dd-chev"><${IconChevron} /></span>
            </div>
            ${open && !disabled && html`
                <div class="dd-pop" ref=${popRef}>
                    ${opts.map(function (o) {
                        return html`
                            <div class=${"dd-opt" + (o.value === value ? " sel" : "")}
                                 onClick=${function () {
                                     if (o.value !== value) onChange(o.value);
                                     setOpen(false);
                                 }}>${o.label}</div>`;
                    })}
                </div>`}
        </div>`;
}
