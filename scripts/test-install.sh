#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { printf 'Usage: %s ARCHIVE [EXPECTED_COMMIT]\n' "$0" >&2; exit 2; }
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
archive=$(cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")
commit=${2:-0123456789abcdef0123456789abcdef01234567}
archive_basename=$(basename -- "$archive")
[[ "$archive_basename" =~ ^bubbl-([0-9]+\.[0-9]+\.[0-9]+)-(x86_64-unknown-linux-musl|x86_64-apple-darwin|aarch64-apple-darwin)\.tar\.gz$ ]] || { printf 'Unexpected archive name.\n' >&2; exit 2; }
version=${BASH_REMATCH[1]}
target=${BASH_REMATCH[2]}
release_name="bubbl-$version-$target.tar.gz"
temp=$(mktemp -d "${TMPDIR:-/tmp}/bubbl-installer-tests.XXXXXX")
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/bin" "$temp/release" "$temp/home" "$temp/data"

cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${BUBBL_TEST_FAIL_GH:-0}" == 1 ]]; then exit 99; fi
if [[ "${BUBBL_TEST_FAIL_ATTESTATION:-0}" == 1 && "$1 $2" == 'attestation verify' ]]; then exit 1; fi
if [[ "$1" == api ]]; then printf '%s\n' "$BUBBL_TEST_COMMIT"; exit 0; fi
if [[ "$1 $2" == 'release list' ]]; then printf 'v%s\n' "$BUBBL_TEST_VERSION"; exit 0; fi
if [[ "$1 $2" == 'release download' ]]; then
  destination=''
  while (($#)); do [[ "$1" != -D ]] || { destination=$2; break; }; shift; done
  mkdir -p "$destination"
  cp "$BUBBL_TEST_RELEASE/$BUBBL_TEST_ARCHIVE_NAME" "$BUBBL_TEST_RELEASE/SHA256SUMS.txt" "$destination/"
fi
exit 0
EOF
cat >"$temp/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=''
output=''
while (($#)); do
  case "$1" in
    -o) output=$2; shift 2 ;;
    http://*|https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  */releases/latest|*/releases/tags/*)
    printf '{\n  "tag_name": "v%s",\n  "draft": false,\n  "prerelease": false,\n  "immutable": true\n}\n' "$BUBBL_TEST_VERSION"
    ;;
  */commits/*)
    printf '{\n  "sha": "%s"\n}\n' "$BUBBL_TEST_COMMIT"
    ;;
  */releases/download/*/SHA256SUMS.txt)
    cp "$BUBBL_TEST_RELEASE/SHA256SUMS.txt" "$output"
    ;;
  */releases/download/*/*)
    cp "$BUBBL_TEST_RELEASE/$BUBBL_TEST_ARCHIVE_NAME" "$output"
    ;;
  *) printf 'unexpected curl URL: %s\n' "$url" >&2; exit 2 ;;
esac
EOF
cat >"$temp/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-} ${3:-}" == 'plugin marketplace list' ]]; then
  if [[ -f "$BUBBL_TEST_MARKET_FILE" ]]; then
    printf '{"marketplaces":[{"name":"bubbl-release","root":"%s"}]}\n' "$(cat "$BUBBL_TEST_MARKET_FILE")"
  else
    printf '{"marketplaces":[]}\n'
  fi
  exit 0
fi
if [[ "${1:-} ${2:-} ${3:-}" == 'plugin marketplace add' ]]; then printf '%s' "$4" >"$BUBBL_TEST_MARKET_FILE"; exit 0; fi
if [[ "${1:-} ${2:-} ${3:-}" == 'plugin marketplace remove' ]]; then rm -f "$BUBBL_TEST_MARKET_FILE"; exit 0; fi
if [[ "${1:-} ${2:-}" == 'plugin add' && "${BUBBL_TEST_FAIL_ADD:-0}" == 1 ]]; then exit 9; fi
exit 0
EOF
chmod +x "$temp/bin/gh" "$temp/bin/codex" "$temp/bin/curl"

export PATH="$temp/bin:$PATH"
export HOME="$temp/home"
export XDG_DATA_HOME="$temp/data"
export BUBBL_TEST_RELEASE="$temp/release"
export BUBBL_TEST_COMMIT="$commit"
export BUBBL_TEST_VERSION="$version"
export BUBBL_TEST_ARCHIVE_NAME="$release_name"
export BUBBL_TEST_MARKET_FILE="$temp/market.txt"
release_archive="$temp/release/$release_name"
set_archive() {
  cp "$1" "$release_archive"
  if command -v sha256sum >/dev/null; then
    hash=$(sha256sum "$release_archive" | awk '{print $1}')
  else
    hash=$(shasum -a 256 "$release_archive" | awk '{print $1}')
  fi
  printf '%s  %s\n' "$hash" "$release_name" >"$temp/release/SHA256SUMS.txt"
}
run_installer() {
  set +e
  bash "$repo/install.sh" --version "$version" --install-root "$temp/installed/marketplace" --strict >"$temp/installer.log" 2>&1
  result=$?
  set -e
  return "$result"
}
run_quick_installer() {
  set +e
  BUBBL_TEST_FAIL_GH=1 bash "$repo/install.sh" --version "$version" --install-root "$temp/quick/marketplace" >"$temp/quick-installer.log" 2>&1
  result=$?
  set -e
  return "$result"
}

set_archive "$archive"
if ! run_quick_installer; then cat "$temp/quick-installer.log" >&2; exit 1; fi
test -x "$temp/quick/marketplace/plugins/bubbl/bin/bubl"
grep -Fq 'checksum-verified immutable release' "$temp/quick-installer.log"
rm -rf -- "$temp/quick" "$BUBBL_TEST_MARKET_FILE"
if ! run_installer; then cat "$temp/installer.log" >&2; exit 1; fi
test -x "$temp/installed/marketplace/plugins/bubbl/bin/bubl"
printf old >"$temp/installed/marketplace/upgrade-sentinel"
if ! run_installer; then cat "$temp/installer.log" >&2; exit 1; fi
test ! -e "$temp/installed/marketplace/upgrade-sentinel"

printf keep >"$temp/installed/marketplace/provenance-sentinel"
export BUBBL_TEST_FAIL_ATTESTATION=1
if run_installer; then printf 'missing attestation was accepted\n' >&2; exit 1; fi
test -e "$temp/installed/marketplace/provenance-sentinel"
export BUBBL_TEST_FAIL_ATTESTATION=0

printf '%064d  %s\n' 0 "$release_name" >"$temp/release/SHA256SUMS.txt"
if run_installer; then printf 'bad checksum was accepted\n' >&2; exit 1; fi
test -e "$temp/installed/marketplace/provenance-sentinel"
set_archive "$archive"

printf '%s' "$temp/other-market" >"$BUBBL_TEST_MARKET_FILE"
if run_installer; then printf 'marketplace collision was accepted\n' >&2; exit 1; fi
test -e "$temp/installed/marketplace/provenance-sentinel"
printf '%s' "$temp/installed/marketplace" >"$BUBBL_TEST_MARKET_FILE"

export BUBBL_TEST_FAIL_ADD=1
if run_installer; then printf 'Codex add failure was accepted\n' >&2; exit 1; fi
test -e "$temp/installed/marketplace/provenance-sentinel"
export BUBBL_TEST_FAIL_ADD=0

for forbidden in raw.githubusercontent 'git clone' 'cargo build'; do
  ! grep -Fq "$forbidden" "$repo/install.ps1" "$repo/install.sh"
done
for required in x86_64-unknown-linux-musl x86_64-apple-darwin aarch64-apple-darwin; do
  grep -Fq "$required" "$repo/install.sh"
done
printf 'shell installer tests passed\n'
