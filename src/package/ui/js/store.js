// store.js - the small amount of state that lives outside the component tree.
//
// The toast and the busy overlay are triggered from anywhere (api helpers,
// event handlers) but rendered once at the app root, so they need a store a
// component can subscribe to. createStore is deliberately minimal - this UI
// does not need anything more.

import { useState, useEffect } from "./preact.js";

export function createStore(initial) {
    let value = initial;
    const subs = new Set();
    return {
        get() { return value; },
        set(next) {
            value = next;
            subs.forEach(function (fn) { fn(next); });
        },
        // subscribe from a component; re-renders it whenever the value changes
        use() {
            const [, bump] = useState(0);
            useEffect(function () {
                const fn = function () { bump(function (n) { return n + 1; }); };
                subs.add(fn);
                return function () { subs.delete(fn); };
            }, []);
            return value;
        }
    };
}

// ------------------------------------------------------------------- toast

export const toastStore = createStore("");
let toastTimer = 0;

export function toast(msg) {
    toastStore.set(msg);
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastStore.set(""); }, 2200);
}

// ------------------------------------------------------------- busy overlay

export const busyStore = createStore({ show: false, msg: "" });
let busyTimer = 0;

export function showBusy(msg) {
    clearTimeout(busyTimer);
    // Avoid a full-screen paint for requests that complete immediately.
    busyTimer = setTimeout(function () { busyStore.set({ show: true, msg: msg }); }, 150);
    busyStore.set({ show: busyStore.get().show, msg: msg });
}

export function hideBusy() {
    clearTimeout(busyTimer);
    busyTimer = 0;
    busyStore.set({ show: false, msg: "" });
}
