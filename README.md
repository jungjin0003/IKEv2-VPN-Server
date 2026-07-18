# Synology package for IKEv2 VPN Server

**English** | [한국어](README.ko.md)

A package for running an IKEv2 VPN Server on Synology NAS devices.

A third-party package that adds a standalone IKEv2/IPsec VPN server to Synology DSM, powered by a pre-compiled strongSwan bundled inside the package.

## Supported NAS platforms
- DSM 7.2 or later
- NAS models using the x86_64 architecture

## Roadmap
We plan to support Synology NAS models on every feasible architecture in the future.

## Supported authentication methods
The services below can run simultaneously, each with its own **independent client IP range**.

| Method | Default IP range | Description | Note |
|----------------|:------------:|---|:-:|
| IKEv2/IPSec MSCHAPv2 | 10.10.0.0/24 | Username/password auth (package-local VPN accounts or DSM user accounts) | |
| IKEv2/IPSec PSK      | 10.11.0.0/24 | Pre-shared key | Beta |
| IKEv2/IPSec RSA      | 10.12.0.0/24 | Client certificate (pubkey); .p12 issued by the package's built-in CA | Beta |
| IKEv2/IPSec EAP-TLS  | 10.13.0.0/24 | EAP-based client certificate | Beta |

- The cipher proposals (IKE/ESP) can be chosen — **Auto / AES-256 / AES-128** — on the "General" page, applied to all methods at once.
- The built-in Windows IKEv2/IPSec client does not support PSK.
- The management UI is shown in Korean or English automatically, based on the browser language.

### IKEv2 MSCHAPv2 with DSM user accounts
Logging in with DSM user accounts over MSCHAPv2 (username/password) requires the **NT hash** of each local account's password. DSM does not officially expose local-account passwords as NT hashes — and of course they cannot be known otherwise. However, Synology DSM keeps NT hashes in its own file `/usr/syno/etc/synosmbpasswd.conf` (as `USERNAME=NThash`) for the SMB service. This package therefore reads the NT hash from that DSM file to authenticate DSM user accounts.

- Each time the service starts/restarts, the hashes are re-read from `synosmbpasswd.conf` and accounts are (re)registered — so adding, removing, or changing the password of an account takes effect after the service is restarted.
- **Disabled (expired) or passwordless accounts are excluded automatically** (e.g. `admin`, `guest`).

## Installation
### Prerequisites
- [Enable SSH](https://www.synology.com/knowledgebase/DSM/tutorial/General_Setup/How_to_login_to_DSM_with_root_permission_via_SSH_Telnet) so you can log in to the NAS.
- If you were running an **L2TP/IPSec VPN server through the VPN Server package, disable it** — this package uses UDP 500/4500 and the two cannot use those ports at the same time.

### Install
1. Open **Package Center**.
2. Click the **Manual Install** button in the top right.
3. Select the `.spk` package downloaded from the [Releases page](../../releases).
4. On the "Confirm settings" step, uncheck **"Run after installation"** in the bottom left.
5. Once the installation finishes, run the following command over SSH:
    - `sudo /var/packages/IKEv2VPN/target/bin/ikev2-setup install`
6. Start the "IKEv2 VPN Server" package in Package Center.

## Uninstallation
- This package requires root privileges, so before removing it you should revoke the root privileges that were granted.
    - Skipping this is not a major security problem, but doing it is recommended.

### Remove
1. Before removing the package, run the command below:
    - `sudo /var/packages/IKEv2VPN/target/bin/ikev2-setup remove`
2. Remove the package from **Package Center**.

## License

This package is distributed under **GPL-2.0-or-later** ([`LICENSE`](LICENSE)). It bundles the `charon`/`swanctl` binaries of strongSwan 6.0.7 (GPL-2.0-or-later, with the OpenSSL linking exception); GMP (LGPL/GPL) is only dynamically linked, not bundled. For the third-party notices and the written offer for corresponding source, see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

- Copyright (C) 2026 jungjin00031
