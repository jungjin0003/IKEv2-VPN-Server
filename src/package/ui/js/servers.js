// servers.js - the four authentication methods.
//
// One definition drives the shared server page, the sidebar entries and the
// overview table, so adding a method is a matter of adding an entry here.

export const SERVER_DEFS = {
    mschapv2: { title: "IKEv2/IPsec MSCHAPv2", enField: "mschapv2",       subnetField: "subnet_mschapv2", dnsField: "dns_mschapv2", certField: "cert_mschapv2", dsmauth: true,  psk: false, cert: true,  clientca: false, connKey: "connections_mschapv2" },
    psk:      { title: "IKEv2/IPsec PSK",      enField: "psk_enabled",    subnetField: "subnet_psk",      dnsField: "dns_psk",                                 dsmauth: false, psk: true,  cert: false, clientca: false, connKey: "connections_psk",      beta: true },
    rsa:      { title: "IKEv2/IPsec RSA",      enField: "rsa_enabled",    subnetField: "subnet_rsa",      dnsField: "dns_rsa",      certField: "cert_rsa",     dsmauth: false, psk: false, cert: true,  clientca: true,  connKey: "connections_rsa",      beta: true },
    eaptls:   { title: "IKEv2/IPsec EAP-TLS",  enField: "eaptls_enabled", subnetField: "subnet_eaptls",   dnsField: "dns_eaptls",   certField: "cert_eaptls",  dsmauth: false, psk: false, cert: true,  clientca: true,  connKey: "connections_eaptls",   beta: true }
};

export const SERVER_KEYS = ["mschapv2", "psk", "rsa", "eaptls"];

// which client profiles each method can hand out
export const PROFILE_BUTTONS = {
    mschapv2: ["ios", "windows", "android", "ca"],
    psk: ["ios_psk", "ca"],
    rsa: ["ca"],
    eaptls: ["ca"]
};
