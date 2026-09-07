#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ikev2-cert-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail_test() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file() {
    [ -f "$1" ] || fail_test "missing file: $1"
}

assert_subject() {
    _expected="$1"
    _file="$2"
    _subject=$(openssl x509 -in "$_file" -noout -subject)
    echo "$_subject" | grep -F "CN = $_expected" >/dev/null \
        || fail_test "expected CN $_expected in $_file, got $_subject"
}

make_ca_cert() {
    _name="$1"
    _key="$TMP/${_name}.key"
    _csr="$TMP/${_name}.csr"
    _cert="$TMP/${_name}.pem"
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
        -subj "/CN=${_name}" -keyout "$_key" -out "$_cert" \
        >/dev/null 2>&1
    printf '%s\n' "$_cert"
}

make_signed_cert() {
    _name="$1"
    _issuer="$2"
    _key="$TMP/${_name}.key"
    _csr="$TMP/${_name}.csr"
    _cert="$TMP/${_name}.pem"
    openssl req -newkey rsa:2048 -nodes -subj "/CN=${_name}" \
        -keyout "$_key" -out "$_csr" >/dev/null 2>&1
    openssl x509 -req -sha256 -days 1 -set_serial "$3" \
        -in "$_csr" -CA "$TMP/${_issuer}.pem" \
        -CAkey "$TMP/${_issuer}.key" -out "$_cert" \
        >/dev/null 2>&1
    printf '%s\n' "$_cert"
}

ROOT_CERT=$(make_ca_cert root)
INT_CERT=$(make_signed_cert intermediate root 2)
LEAF_CERT=$(make_signed_cert server intermediate 3)

SYNO_CERT_ARCHIVE="$TMP/archive"
SYNO_CERT_DIR="$TMP/default"
CERT_DIR="$TMP/cert"
SWANCTL_ETC="$TMP/swanctl"
CLIENTCA_DIR="$TMP/clientca"
IKEV2_HOSTNAME=""
IKEV2_CERT_MSCHAPV2="1"
IKEV2_CERT_RSA="1"
IKEV2_CERT_EAPTLS="1"
IKEV2_ENABLE_RSA="no"
IKEV2_ENABLE_EAPTLS="no"
mkdir -p "$SYNO_CERT_ARCHIVE/1"
cp "$LEAF_CERT" "$SYNO_CERT_ARCHIVE/1/cert.pem"
cp "$TMP/server.key" "$SYNO_CERT_ARCHIVE/1/privkey.pem"

# The library is intentionally sourced after its path variables are set. It
# defines functions only, so this test can exercise the installer in isolation.
# The package sources are normalized to LF by build.sh; normalize the checkout
# copy here so the fixture also runs from a Windows CRLF worktree.
CERT_LIB="$TMP/cert.sh"
sed 's/\r$//' "$ROOT/src/package/bin/lib/cert.sh" > "$CERT_LIB"
# shellcheck disable=SC1090
. "$CERT_LIB"

run_install() {
    rm -rf "$SWANCTL_ETC" "$CERT_DIR"
    mkdir -p "$SWANCTL_ETC" "$CERT_DIR"
    install_server_cert mschapv2 1
    assert_file "$SWANCTL_ETC/x509/server-cert-mschapv2.pem"
    assert_subject server "$SWANCTL_ETC/x509/server-cert-mschapv2.pem"
    assert_subject root "$CERT_DIR/mschapv2.ca.pem"
    assert_subject root "$SWANCTL_ETC/x509ca/server-chain-mschapv2-002.pem"
    assert_subject intermediate "$SWANCTL_ETC/x509ca/server-chain-mschapv2-001.pem"
}

# A chain embedded after the leaf in cert.pem is split without losing either
# authority.
cat "$LEAF_CERT" "$INT_CERT" "$ROOT_CERT" > "$SYNO_CERT_ARCHIVE/1/cert.pem"
rm -f "$SYNO_CERT_ARCHIVE/1/chain.pem" "$SYNO_CERT_ARCHIVE/1/fullchain.pem"
run_install

# The canonical CA downloaded by the UI is the final authority, not the first
# intermediate in the server chain.
install_cert
assert_subject root "$CERT_DIR/ca.pem"

# A conventional DSM fullchain.pem has the leaf first and the CA chain after it.
cp "$LEAF_CERT" "$SYNO_CERT_ARCHIVE/1/cert.pem"
cat "$LEAF_CERT" "$INT_CERT" "$ROOT_CERT" > "$SYNO_CERT_ARCHIVE/1/fullchain.pem"
run_install

# A DSM chain.pem contains authorities only and is still split into one file per
# certificate for the strongSwan credential directory.
rm -f "$SYNO_CERT_ARCHIVE/1/fullchain.pem"
cat "$INT_CERT" "$ROOT_CERT" > "$SYNO_CERT_ARCHIVE/1/chain.pem"
run_install

# A self-signed leaf remains usable and is exposed as the profile trust anchor.
SELF_CERT=$(make_ca_cert self-signed)
cp "$SELF_CERT" "$SYNO_CERT_ARCHIVE/1/cert.pem"
cp "$TMP/self-signed.key" "$SYNO_CERT_ARCHIVE/1/privkey.pem"
rm -f "$SYNO_CERT_ARCHIVE/1/chain.pem"
rm -f "$SYNO_CERT_ARCHIVE/1/fullchain.pem"
run_install_self_signed() {
    rm -rf "$SWANCTL_ETC" "$CERT_DIR"
    mkdir -p "$SWANCTL_ETC" "$CERT_DIR"
    install_server_cert mschapv2 1
    assert_file "$CERT_DIR/mschapv2.selfsigned"
    assert_file "$CERT_DIR/mschapv2.ca.pem"
    assert_subject self-signed "$CERT_DIR/mschapv2.ca.pem"
}
run_install_self_signed

echo "PASS: certificate chain fixtures preserve the leaf, every authority, and the trust anchor"
