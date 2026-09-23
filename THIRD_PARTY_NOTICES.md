# Third-Party Notices

This package (IKEv2 VPN Server for Synology DSM) is distributed under the
**GNU General Public License, version 2 or (at your option) any later version
(GPL-2.0-or-later)**. See [`LICENSE`](LICENSE) for the full GPLv2 text.

    IKEv2 VPN Server — a DSM package adding an IKEv2/IPsec VPN server
    Copyright (C) 2026 jungjin0003 (CrazyHacker)

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation; either version 2 of the License, or (at your option)
    any later version.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
    more details.

The package **bundles the following third-party software**. Their license
terms are reproduced below and, for the redistributable pieces, are also
shipped inside the `.spk` (under `target/` and `licenses/`).

---

## 1. strongSwan (bundled — charon daemon and swanctl CLI)

- **Version:** @STRONGSWAN_VERSION@
- **Files:** `target/strongswan/libexec/ipsec/charon`,
  `target/strongswan/sbin/swanctl`, and the plugin config snippets under
  `target/strongswan/strongswan.d/charon/`.
- **License:** GPL-2.0-or-later, with a special OpenSSL linking exception and
  BSD-/RSA-licensed portions in some crypto plugins. The verbatim strongSwan
  license notice is in [`licenses/strongswan-LICENSE.txt`](licenses/strongswan-LICENSE.txt);
  the GPLv2 body is in [`LICENSE`](LICENSE).
- **Copyright:** © the strongSwan project and contributors (see the source
  files for per-file copyright information).
- **Upstream / source:** <https://www.strongswan.org/> ·
  source tarball <https://download.strongswan.org/strongswan-@STRONGSWAN_VERSION@.tar.bz2> ·
  git <https://github.com/strongswan/strongswan> (tag `@STRONGSWAN_VERSION@`).

### Written offer for corresponding source (GPLv2 §3)

The strongSwan binaries in this package are distributed in compiled form. The
complete corresponding source code is the unmodified strongSwan @STRONGSWAN_VERSION@ release
available at the upstream URLs above. This package applies **no source
modifications** to strongSwan — it only compiles it with a fixed set of
configure options. The exact build recipe (download, configure flags, install
layout) is the [`build.sh`](build.sh) script in this repository, which
reproduces the bundled binaries. If for any reason the upstream source becomes
unavailable, the maintainer will provide a copy of the corresponding source on
request.

### Mandatory notices for bundled strongSwan crypto plugins

This build enables the `md4`, `md5`, and `des` plugins, which carry additional
required notices:

- The MD4 and MD5 implementations are from RSA Data Security, Inc. As required,
  this package includes the phrase:
  **"derived from the RSA Data Security, Inc. MD5 Message-Digest Algorithm"**.
- The DES implementation (des plugin) and Blowfish implementation are under a
  BSD-style license that includes an advertising clause; see the corresponding
  source files in the strongSwan distribution for details.

---

## 2. GNU MP (GMP) — dynamically linked, NOT bundled

- **License:** dual GNU LGPL-2.1-or-later / GNU GPL-2.0-or-later.
- **Usage:** the bundled `charon`/`swanctl` binaries link **dynamically** at
  runtime against the target system's own `libgmp.so` (provided by DSM). GMP
  itself is **not included in or distributed by** this package.
- **Copyright / source:** © the GMP developers — <https://gmplib.org/>.

---

## 3. OpenSSL (bundled: statically linked into strongSwan)

- **Version:** @OPENSSL_VERSION@
- **Files:** none of its own. `libcrypto.a` is linked into the bundled `charon`
  and `swanctl` binaries, so no OpenSSL shared library ships with the package.
- **License:** Apache-2.0. The verbatim license text is in
  [`licenses/openssl-LICENSE.txt`](licenses/openssl-LICENSE.txt).
- **Copyright:** Copyright © 1998-2026 The OpenSSL Project Authors and other
  contributors listed in the source distribution.
- **Upstream / source:** <https://www.openssl.org/> · source tarball
  <https://github.com/openssl/openssl/releases/download/openssl-@OPENSSL_VERSION@/openssl-@OPENSSL_VERSION@.tar.gz>
  · git <https://github.com/openssl/openssl> (tag `openssl-@OPENSSL_VERSION@`).
- **Modifications:** none. The build uses `no-shared`, `no-module` and `no-dso`,
  then links the resulting static cryptography library into strongSwan.

---

## 4. Preact + htm (bundled: management UI)

- **Version:** the `htm/preact/standalone` build from htm 3.1.1, which bundles
  Preact, its hooks and htm's tagged-template renderer into one ES module.
- **Files:** `target/ui/vendor/preact-standalone.module.js`
  (SHA-256 `72284e8e9079c87817145df1110f74e8a2aa040b2fc384922e18dfcb46fc1fd7`).
- **License:** Preact is MIT — see
  [`licenses/preact-LICENSE.txt`](licenses/preact-LICENSE.txt);
  htm is Apache-2.0 — see [`licenses/htm-LICENSE.txt`](licenses/htm-LICENSE.txt).
- **Copyright:** © 2015-present Jason Miller and the Preact contributors.
- **Upstream / source:** <https://preactjs.com/> · <https://github.com/preactjs/preact>
  · <https://github.com/developit/htm> · bundle
  <https://unpkg.com/htm@3.1.1/preact/standalone.module.js>.
- **Modifications:** none. The file is the published bundle, vendored verbatim
  so the package needs no build tooling and loads nothing from the network.

---
## 5. ipset (bundled: the ipset command line tool)

- **Version:** @IPSET_VERSION@
- **Files:** `target/ipset/ipset`.
- **License:** GPL-2.0-only. The verbatim license text is in
  [`licenses/ipset-LICENSE.txt`](licenses/ipset-LICENSE.txt); the GPLv2 body is
  also in [`LICENSE`](LICENSE).
- **Copyright:** © Jozsef Kadlecsik and the Netfilter project (see the source
  files for per-file copyright information).
- **Upstream / source:** <https://ipset.netfilter.org/> ·
  source tarball <https://ipset.netfilter.org/ipset-@IPSET_VERSION@.tar.bz2> ·
  git <https://git.netfilter.org/ipset/>.

### Written offer for corresponding source (GPLv2 §3)

The ipset binary in this package is distributed in compiled form. The complete
corresponding source code is the unmodified ipset @IPSET_VERSION@ release available at the
upstream URLs above. This package applies **no source modifications** to ipset;
it only compiles it with a fixed set of configure options. The exact build
recipe (download, configure flags, install layout) is the
[`build.sh`](build.sh) script in this repository, which reproduces the bundled
binary. If for any reason the upstream source becomes unavailable, the
maintainer will provide a copy of the corresponding source on request.

---

## 6. libmnl (bundled: statically linked into the ipset binary)

- **Version:** @LIBMNL_VERSION@
- **Files:** none of its own. libmnl is compiled as a static library and linked
  into `target/ipset/ipset`, so no `libmnl.so` ships with the package.
- **License:** LGPL-2.1-or-later. The verbatim license text is in
  [`licenses/libmnl-LICENSE.txt`](licenses/libmnl-LICENSE.txt).
- **Copyright:** © Pablo Neira Ayuso and the Netfilter project (see the source
  files for per-file copyright information).
- **Upstream / source:** <https://netfilter.org/projects/libmnl/> ·
  source tarball <https://www.netfilter.org/projects/libmnl/files/libmnl-@LIBMNL_VERSION@.tar.bz2> ·
  git <https://git.netfilter.org/libmnl/>.

### Relinking the bundled ipset with a modified libmnl (LGPL-2.1 §6)

Because libmnl is linked statically, the LGPL requires the means to relink the
resulting work against a modified libmnl. The [`build.sh`](build.sh) script in
this repository is that means: it downloads libmnl @LIBMNL_VERSION@ and ipset @IPSET_VERSION@,
builds libmnl into a private prefix, and links ipset against it. Pointing the
libmnl stage at a modified source tree and rerunning the script produces an
ipset binary linked against that version. The maintainer will provide the
corresponding source and object files on request.

---

## Icon

The package icon (`icon.png` and the generated `PACKAGE_ICON*.PNG` /
`ui/images/*`) is AI-generated artwork; no third-party attribution is required.
