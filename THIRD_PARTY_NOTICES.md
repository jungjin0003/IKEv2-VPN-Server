# Third-Party Notices

This package (IKEv2 VPN Server for Synology DSM) is distributed under the
**GNU General Public License, version 2 or (at your option) any later version
(GPL-2.0-or-later)**. See [`LICENSE`](LICENSE) for the full GPLv2 text.

    IKEv2 VPN Server — a DSM package adding an IKEv2/IPsec VPN server
    Copyright (C) 2026 jungjin00031

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

- **Version:** 6.0.7
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
  source tarball <https://download.strongswan.org/strongswan-6.0.7.tar.bz2> ·
  git <https://github.com/strongswan/strongswan> (tag `6.0.7`).

### Written offer for corresponding source (GPLv2 §3)

The strongSwan binaries in this package are distributed in compiled form. The
complete corresponding source code is the unmodified strongSwan 6.0.7 release
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

## Icon

The package icon (`icon.png` and the generated `PACKAGE_ICON*.PNG` /
`ui/images/*`) is AI-generated artwork; no third-party attribution is required.
