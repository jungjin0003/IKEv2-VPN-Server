# cert.sh - the server certificate each VPN server presents, and the package's
# own CA that issues client certificates.
#
# Each cert-based VPN server (mschapv2/rsa/eaptls) presents a certificate the
# user picked from DSM's certificate store (IKEV2_CERT_<scope> = archive id;
# "" = DSM system default). Only when DSM has no usable certificate at all is a
# single temporary self-signed cert generated so the service can still start.

cert_cn() {
    openssl x509 -in "$1" -noout -subject 2>/dev/null \
        | sed -n 's/.*CN[ ]*=[ ]*\([^,/]*\).*/\1/p' | head -n 1
}

get_leftid() {
    LEFTID="$IKEV2_HOSTNAME"
    [ -n "$LEFTID" ] || LEFTID=$(cert_cn "${CERT_DIR}/server-cert.pem")
    [ -n "$LEFTID" ] || LEFTID=$(hostname)
}

# ----------------------------------------------------------------- server cert

# Return the number of PEM certificate blocks in a file.
pem_cert_count() {
    _input="$1"
    _count=$(grep -c -- '-----BEGIN CERTIFICATE-----' "$_input" 2>/dev/null || true)
    printf '%s\n' "${_count:-0}"
}

# Copy one certificate from a PEM bundle. OpenSSL's default file loader stops
# after the first certificate, so bundle members must be handled explicitly.
extract_pem_cert() {
    _input="$1"; _number="$2"; _output="$3"
    awk -v wanted="$_number" '
        /-----BEGIN CERTIFICATE-----/ { n++; capture=(n == wanted) }
        capture { print }
        capture && /-----END CERTIFICATE-----/ { exit }
    ' "$_input" > "$_output"
    [ -s "$_output" ] || { rm -f "$_output"; return 1; }
}

# Split a certificate bundle into separately loadable files. strongSwan and
# the DSM profile generator each consume one certificate per file.
split_pem_certs() {
    _input="$1"; _prefix="$2"; _start="${3:-1}"
    _total=$(pem_cert_count "$_input")
    [ "$_total" -gt 0 ] || return 1

    _out_index=1
    _number="$_start"
    while [ "$_number" -le "$_total" ]; do
        _output="${_prefix}-$(printf '%03d' "$_out_index").pem"
        extract_pem_cert "$_input" "$_number" "$_output" || return 1
        openssl x509 -in "$_output" -noout >/dev/null 2>&1 || {
            rm -f "$_output"
            return 1
        }
        _out_index=$((_out_index + 1))
        _number=$((_number + 1))
    done

    PEM_CERT_COUNT=$((_out_index - 1))
}

# best-effort description for a DSM archive cert id, from the archive INFO json
dsm_cert_desc() {
    [ -f "${SYNO_CERT_ARCHIVE}/INFO" ] || return 0
    sed 's/},/}\n/g' "${SYNO_CERT_ARCHIVE}/INFO" 2>/dev/null \
        | grep "\"$1\"" \
        | sed -n 's/.*"desc"[^"]*"\([^"]*\)".*/\1/p' | head -n 1
}

# list installable DSM certificates as "id|label" (label = desc, else CN)
dsm_cert_list() {
    [ -d "$SYNO_CERT_ARCHIVE" ] || return 0
    for d in "$SYNO_CERT_ARCHIVE"/*/; do
        _cid=$(basename "$d")
        [ "$_cid" = "*" ] && continue
        [ -f "${d}cert.pem" ] && [ -f "${d}privkey.pem" ] || continue
        _lbl=$(dsm_cert_desc "$_cid")
        [ -n "$_lbl" ] || _lbl=$(cert_cn "${d}cert.pem")
        [ -n "$_lbl" ] || _lbl="$_cid"
        printf '%s|%s\n' "$_cid" "$_lbl"
    done
}

# archive id of DSM's default certificate (from _archive/DEFAULT, else whatever
# the system/default slot links to); empty if it can't be determined
dsm_cert_default() {
    _d=""
    [ -f "${SYNO_CERT_ARCHIVE}/DEFAULT" ] && _d=$(head -n1 "${SYNO_CERT_ARCHIVE}/DEFAULT" 2>/dev/null | tr -d ' \t\r\n')
    if [ -z "$_d" ] && [ -L "$SYNO_CERT_DIR" ]; then
        _d=$(basename "$(readlink -f "$SYNO_CERT_DIR" 2>/dev/null)" 2>/dev/null)
    fi
    [ -n "$_d" ] && [ -f "${SYNO_CERT_ARCHIVE}/${_d}/cert.pem" ] && printf '%s\n' "$_d"
}

# resolve a selected cert id to a source dir: a valid archive id -> its dir;
# empty id -> DSM's default certificate; otherwise the system default slot;
# otherwise the first available archive cert. Prints the dir (return 0), or
# returns 1 when DSM has no usable cert at all.
dsm_cert_src() {
    _id="$1"
    [ -n "$_id" ] || _id=$(dsm_cert_default)
    if [ -n "$_id" ] && [ -f "${SYNO_CERT_ARCHIVE}/${_id}/cert.pem" ] && [ -f "${SYNO_CERT_ARCHIVE}/${_id}/privkey.pem" ]; then
        printf '%s\n' "${SYNO_CERT_ARCHIVE}/${_id}"; return 0
    fi
    if [ -f "${SYNO_CERT_DIR}/cert.pem" ] && [ -f "${SYNO_CERT_DIR}/privkey.pem" ]; then
        printf '%s\n' "$SYNO_CERT_DIR"; return 0
    fi
    for d in "$SYNO_CERT_ARCHIVE"/*/; do
        [ -f "${d}cert.pem" ] && [ -f "${d}privkey.pem" ] && { printf '%s\n' "${d%/}"; return 0; }
    done
    return 1
}

# generate the shared temporary self-signed cert (only when DSM has none),
# using the system openssl inside DSM
ensure_temp_cert() {
    [ -f "${CERT_DIR}/temp-cert.pem" ] && [ -f "${CERT_DIR}/temp-key.pem" ] && return 0
    _cn="$IKEV2_HOSTNAME"
    [ -n "$_cn" ] || _cn=$(hostname 2>/dev/null)
    [ -n "$_cn" ] || _cn="ikev2-vpn"
    mkdir -p "$CERT_DIR"
    umask 077
    # -addext needs openssl >= 1.1.1 (DSM 7.2); fall back to a plain
    # self-signed cert if this openssl is older.
    openssl req -x509 -new -nodes -newkey rsa:2048 -sha256 \
        -keyout "${CERT_DIR}/temp-key.pem" -out "${CERT_DIR}/temp-cert.pem" \
        -days 825 -subj "/CN=${_cn}" \
        -addext "subjectAltName=DNS:${_cn}" \
        -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1 \
    || openssl req -x509 -new -nodes -newkey rsa:2048 -sha256 \
        -keyout "${CERT_DIR}/temp-key.pem" -out "${CERT_DIR}/temp-cert.pem" \
        -days 825 -subj "/CN=${_cn}" >/dev/null 2>&1 \
    || fail "temporary certificate generation failed"
    chmod 600 "${CERT_DIR}/temp-key.pem"
    log "no DSM certificate available; generated temporary self-signed cert (CN=${_cn})"
}

# install the certificate for one cert-based scope into swanctl.
#   $1 = scope (mschapv2|rsa|eaptls), $2 = selected DSM cert id
# Produces x509/server-cert-<scope>.pem, private/server-key-<scope>.pem,
# separately numbered x509ca/server-chain-<scope>-*.pem files, and records
# CERT_DIR/<scope>.leftid, <scope>.ca.pem, <scope>.selfsigned,
# <scope>.temporary.
install_server_cert() {
    _scope="$1"; _cid="$2"
    _crt="${SWANCTL_ETC}/x509/server-cert-${_scope}.pem"
    _key="${SWANCTL_ETC}/private/server-key-${_scope}.pem"
    _chain_prefix="${SWANCTL_ETC}/x509ca/server-chain-${_scope}"
    _profile_ca="${CERT_DIR}/${_scope}.ca.pem"
    mkdir -p "${SWANCTL_ETC}/x509" "${SWANCTL_ETC}/private" "${SWANCTL_ETC}/x509ca" "$CERT_DIR"

    _src=$(dsm_cert_src "$_cid") || _src=""
    if [ -n "$_src" ]; then
        # Keep the leaf separate from all issuing authorities. DSM commonly
        # stores a leaf-only cert.pem, but some stores put the full chain in it.
        # A file no certificate can be read out of is taken as it stands rather
        # than treated as fatal, so a certificate store this cannot parse costs
        # the chain and not the whole service.
        extract_pem_cert "${_src}/cert.pem" 1 "$_crt" || {
            log "WARN: no certificate found in ${_src}/cert.pem; installing it unchanged"
            cp -f "${_src}/cert.pem" "$_crt"
        }
        cp -f "${_src}/privkey.pem" "$_key"
        rm -f "${CERT_DIR}/${_scope}.temporary"
    else
        ensure_temp_cert
        cp -f "${CERT_DIR}/temp-cert.pem" "$_crt"
        cp -f "${CERT_DIR}/temp-key.pem"  "$_key"
        : > "${CERT_DIR}/${_scope}.temporary"
    fi
    chmod 600 "$_key"

    # Each authority gets its own file because strongSwan loads one PEM
    # certificate per credential path. Prefer DSM's chain.pem; otherwise use
    # fullchain.pem (skipping its leaf), or the additional members in cert.pem.
    rm -f "${SWANCTL_ETC}/x509ca/server-chain-${_scope}.pem" \
          "${_chain_prefix}-"*.pem "$_profile_ca" "${CERT_DIR}/${_scope}.selfsigned"
    _chain_input=""
    _chain_start=1
    if [ -n "$_src" ] && [ -s "${_src}/chain.pem" ]; then
        _chain_input="${_src}/chain.pem"
    elif [ -n "$_src" ] && [ -s "${_src}/fullchain.pem" ]; then
        _chain_input="${_src}/fullchain.pem"
        _chain_start=2
    elif [ -n "$_src" ] && [ "$(pem_cert_count "${_src}/cert.pem")" -gt 1 ]; then
        _chain_input="${_src}/cert.pem"
        _chain_start=2
    fi
    if [ -n "$_chain_input" ]; then
        split_pem_certs "$_chain_input" "$_chain_prefix" "$_chain_start" \
            || log "WARN: no usable CA certificate in $_chain_input; the chain is not installed"
    fi

    _sh=$(openssl x509 -in "$_crt" -noout -subject_hash 2>/dev/null)
    _ih=$(openssl x509 -in "$_crt" -noout -issuer_hash 2>/dev/null)
    if [ -n "$_sh" ] && [ "$_sh" = "$_ih" ]; then
        # A self-signed leaf is also the trust anchor. Keep it in the same
        # separately loadable credential layout as a normal chain.
        rm -f "${_chain_prefix}-"*.pem
        extract_pem_cert "$_crt" 1 "${_chain_prefix}-001.pem" \
            || log "WARN: could not install the self-signed certificate as its own trust anchor"
        echo "yes" > "${CERT_DIR}/${_scope}.selfsigned"
    fi

    # Client profiles should trust the anchor of the chain, not the authority
    # that signed the server certificate. The anchor is the certificate that
    # issued itself, which is what the client already has to hold for the path
    # to complete. A chain that ends before its anchor gives up its last entry.
    _anchor=""
    for _f in "${_chain_prefix}-"*.pem; do
        [ -f "$_f" ] || continue
        _anchor="$_f"
        _fs=$(openssl x509 -in "$_f" -noout -subject_hash 2>/dev/null)
        _fi=$(openssl x509 -in "$_f" -noout -issuer_hash 2>/dev/null)
        [ -n "$_fs" ] && [ "$_fs" = "$_fi" ] && break
    done
    [ -n "$_anchor" ] && cp -f "$_anchor" "$_profile_ca"

    # IKE identity presented to clients: configured hostname, else the cert CN
    _lid="$IKEV2_HOSTNAME"
    [ -n "$_lid" ] || _lid=$(cert_cn "$_crt")
    [ -n "$_lid" ] || _lid=$(hostname)
    printf '%s\n' "$_lid" > "${CERT_DIR}/${_scope}.leftid"
}

install_cert() {
    mkdir -p "$CERT_DIR" "${SWANCTL_ETC}/x509" "${SWANCTL_ETC}/private" "${SWANCTL_ETC}/x509ca"

    # drop pre-per-scope files so swanctl doesn't auto-load a stale server key
    rm -f "${SWANCTL_ETC}/x509/server-cert.pem" "${SWANCTL_ETC}/private/server-key.pem" \
          "${SWANCTL_ETC}/x509ca/server-chain-ca.pem" 2>/dev/null

    # per cert-based server: install its chosen DSM certificate (or temp)
    install_server_cert mschapv2 "$IKEV2_CERT_MSCHAPV2"
    install_server_cert rsa      "$IKEV2_CERT_RSA"
    install_server_cert eaptls   "$IKEV2_CERT_EAPTLS"

    # canonical set used by client-profile generation, get_leftid and status -
    # mirrors the MSCHAPv2 (primary) server's certificate
    cp -f "${SWANCTL_ETC}/x509/server-cert-mschapv2.pem"  "${CERT_DIR}/server-cert.pem"
    cp -f "${SWANCTL_ETC}/private/server-key-mschapv2.pem" "${CERT_DIR}/server-key.pem"
    chmod 600 "${CERT_DIR}/server-key.pem"
    rm -f "${CERT_DIR}/ca.pem"
    if [ -f "${CERT_DIR}/mschapv2.ca.pem" ]; then
        cp -f "${CERT_DIR}/mschapv2.ca.pem" "${CERT_DIR}/ca.pem"
    else
        rm -f "${CERT_DIR}/ca.pem"
    fi
    [ -f "${CERT_DIR}/mschapv2.selfsigned" ] && echo "yes" > "${CERT_DIR}/self-signed" || rm -f "${CERT_DIR}/self-signed"
    [ -f "${CERT_DIR}/mschapv2.temporary" ]  && : > "${CERT_DIR}/temporary" || rm -f "${CERT_DIR}/temporary"

    # client CA (for RSA / EAP-TLS remote pubkey auth)
    if [ "$IKEV2_ENABLE_RSA" = "yes" ] || [ "$IKEV2_ENABLE_EAPTLS" = "yes" ]; then
        ensure_client_ca
        cp -f "${CLIENTCA_DIR}/ca.pem" "${SWANCTL_ETC}/x509ca/clientca.pem"
    else
        rm -f "${SWANCTL_ETC}/x509ca/clientca.pem" 2>/dev/null
    fi
}

# --------------------------------------------------------------- client CA

ensure_client_ca() {
    [ -f "${CLIENTCA_DIR}/ca.pem" ] && [ -f "${CLIENTCA_DIR}/ca.key" ] && return 0
    mkdir -p "$ISSUED_DIR"
    umask 077
    openssl req -x509 -new -nodes -newkey rsa:2048 -sha256 \
        -keyout "${CLIENTCA_DIR}/ca.key" -out "${CLIENTCA_DIR}/ca.pem" \
        -days 3650 -subj "/CN=IKEv2VPN Client CA" >/dev/null 2>&1 \
        || fail "client CA generation failed"
    own_pkg "$CLIENTCA_DIR"
    log "client CA generated"
}

cert_issue() {
    NAME="$1"; P12PASS="$2"; OUTFILE="$3"
    printf '%s' "$NAME" | grep -Eq '^[A-Za-z0-9._-]{1,32}$' || fail "invalid cert name"
    [ -n "$P12PASS" ] || fail "empty p12 password"
    [ -n "$OUTFILE" ] || fail "no output file"

    ensure_client_ca
    TMP="${VAR}/certtmp.$$"
    mkdir -p "$TMP"
    umask 077

    openssl req -new -nodes -newkey rsa:2048 -sha256 \
        -keyout "${TMP}/key.pem" -out "${TMP}/csr.pem" \
        -subj "/CN=${NAME}" >/dev/null 2>&1 || { rm -rf "$TMP"; fail "csr failed"; }

    printf 'extendedKeyUsage=clientAuth\nkeyUsage=digitalSignature\nsubjectAltName=DNS:%s\n' "$NAME" \
        > "${TMP}/ext.cnf"

    openssl x509 -req -in "${TMP}/csr.pem" -sha256 \
        -CA "${CLIENTCA_DIR}/ca.pem" -CAkey "${CLIENTCA_DIR}/ca.key" \
        -CAcreateserial -days 1095 -extfile "${TMP}/ext.cnf" \
        -out "${TMP}/cert.pem" >/dev/null 2>&1 || { rm -rf "$TMP"; fail "signing failed"; }

    openssl pkcs12 -export \
        -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
        -certfile "${CLIENTCA_DIR}/ca.pem" \
        -name "IKEv2 VPN (${NAME})" \
        -passout "pass:${P12PASS}" -out "$OUTFILE" >/dev/null 2>&1 \
        || { rm -rf "$TMP"; fail "p12 export failed"; }

    mkdir -p "$ISSUED_DIR"
    cp -f "${TMP}/cert.pem" "${ISSUED_DIR}/${NAME}.pem"
    rm -rf "$TMP"
    own_pkg "$CLIENTCA_DIR"

    # when called through sudo, let the calling (package) user read the p12
    if [ -n "$SUDO_UID" ]; then
        chown "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$OUTFILE" 2>/dev/null
    fi
    log "client certificate issued: ${NAME}"
}

cert_list() {
    [ -d "$ISSUED_DIR" ] || return 0
    for f in "$ISSUED_DIR"/*.pem; do
        [ -f "$f" ] || continue
        N=$(basename "$f" .pem)
        EXP=$(openssl x509 -in "$f" -noout -enddate 2>/dev/null | cut -d= -f2)
        echo "${N}|${EXP}"
    done
}

cert_del() {
    printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._-]{1,32}$' || fail "invalid cert name"
    rm -f "${ISSUED_DIR}/$1.pem"
    log "client certificate record removed: $1 (note: not revoked - no CRL)"
}
