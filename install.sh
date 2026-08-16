#!/usr/bin/env bash
set -euo pipefail

repository='BubbleBuffer/Bubbl'
marketplace='bubbl-release'
signer_workflow='github.com/BubbleBuffer/Bubbl/.github/workflows/release.yml'
version=''
strict=0
install_root="${XDG_DATA_HOME:-$HOME/.local/share}/bubbl/marketplace"

usage() {
  printf 'Usage: %s [--version X.Y.Z] [--install-root PATH] [--strict]\n' "$0"
  printf 'Default: install an immutable release with SHA-256 and package checks. This does not require GitHub CLI or a GitHub account.\n'
  printf 'Strict: add GitHub release and artifact-attestation verification; requires an authenticated GitHub CLI.\n'
}
while (($#)); do
  case "$1" in
    --version) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; version=$2; shift 2 ;;
    --install-root) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; install_root=$2; shift 2 ;;
    --strict) strict=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
if [[ -n "$version" && ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Version must be an exact X.Y.Z release.\n' >&2
  exit 2
fi

for command_name in codex tar; do
  command -v "$command_name" >/dev/null || { printf '%s is required.\n' "$command_name" >&2; exit 1; }
done
if ((strict)); then
  command -v gh >/dev/null || { printf 'Strict verification requires GitHub CLI (gh).\n' >&2; exit 1; }
  gh auth status >/dev/null
  gh attestation verify --help >/dev/null
  gh release verify --help >/dev/null
else
  command -v curl >/dev/null || { printf 'curl is required.\n' >&2; exit 1; }
fi
codex plugin --help >/dev/null

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) target='x86_64-unknown-linux-musl' ;;
  Darwin:x86_64) target='x86_64-apple-darwin' ;;
  Darwin:arm64|Darwin:aarch64) target='aarch64-apple-darwin' ;;
  *) printf 'Bubbl has no release archive for %s/%s.\n' "$(uname -s)" "$(uname -m)" >&2; exit 1 ;;
esac

if ((strict)); then
  if [[ -n "$version" ]]; then
    tag="v$version"
  else
    tag=$(gh release list -R "$repository" --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName')
    [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || { printf 'No stable Bubbl release found.\n' >&2; exit 1; }
    version=${BASH_REMATCH[1]}
  fi
  source_commit=$(gh api "repos/$repository/commits/$tag" --jq .sha | tr '[:upper:]' '[:lower:]')
else
  api_root="https://api.github.com/repos/$repository"
  if [[ -n "$version" ]]; then release_api="$api_root/releases/tags/v$version"; else release_api="$api_root/releases/latest"; fi
  release_json=$(curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: Bubbl-Installer' "$release_api")
  grep -Eq '"draft"[[:space:]]*:[[:space:]]*false' <<<"$release_json" || { printf 'Bubbl release is a draft.\n' >&2; exit 1; }
  grep -Eq '"prerelease"[[:space:]]*:[[:space:]]*false' <<<"$release_json" || { printf 'Bubbl release is a prerelease.\n' >&2; exit 1; }
  grep -Eq '"immutable"[[:space:]]*:[[:space:]]*true' <<<"$release_json" || { printf 'Bubbl release is not immutable.\n' >&2; exit 1; }
  tag=$(sed -nE 's/^[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' <<<"$release_json" | head -n 1)
  [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || { printf 'No stable Bubbl release found.\n' >&2; exit 1; }
  version=${BASH_REMATCH[1]}
  commit_json=$(curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: Bubbl-Installer' "$api_root/commits/$tag")
  source_commit=$(sed -nE 's/^[[:space:]]*"sha"[[:space:]]*:[[:space:]]*"([0-9a-fA-F]{40})".*/\1/p' <<<"$commit_json" | head -n 1 | tr '[:upper:]' '[:lower:]')
fi
archive_name="bubbl-$version-$target.tar.gz"
source_ref="refs/tags/$tag"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || { printf 'Could not resolve the release commit.\n' >&2; exit 1; }

temp=$(mktemp -d "${TMPDIR:-/tmp}/bubbl-install.XXXXXX")
incoming=''
previous=''
cleanup() {
  rm -rf -- "$temp"
  [[ -z "$incoming" || ! -e "$incoming" ]] || rm -rf -- "$incoming"
}
trap cleanup EXIT

archive="$temp/$archive_name"
checksums="$temp/SHA256SUMS.txt"
if ((strict)); then
  gh release verify "$tag" -R "$repository"
  script_path=$(cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
  gh release verify-asset "$tag" "$script_path" -R "$repository"
  gh attestation verify "$script_path" -R "$repository" --signer-workflow "$signer_workflow" --source-ref "$source_ref" --source-digest "$source_commit" --deny-self-hosted-runners
  gh release download "$tag" -R "$repository" -D "$temp" -p "$archive_name" -p SHA256SUMS.txt
  for asset in "$archive" "$checksums"; do
    gh release verify-asset "$tag" "$asset" -R "$repository"
    gh attestation verify "$asset" -R "$repository" --signer-workflow "$signer_workflow" --source-ref "$source_ref" --source-digest "$source_commit" --deny-self-hosted-runners
  done
else
  release_base="https://github.com/$repository/releases/download/$tag"
  curl -fL --retry 3 --retry-delay 1 "$release_base/$archive_name" -o "$archive"
  curl -fL --retry 3 --retry-delay 1 "$release_base/SHA256SUMS.txt" -o "$checksums"
fi
expected_hash=$(awk -v name="$archive_name" '$2 == name && $1 ~ /^[0-9a-fA-F]{64}$/ { print tolower($1); exit }' "$checksums")
[[ -n "$expected_hash" ]] || { printf '%s is absent from SHA256SUMS.txt.\n' "$archive_name" >&2; exit 1; }
if command -v sha256sum >/dev/null; then
  actual_hash=$(sha256sum "$archive" | awk '{print $1}')
else
  actual_hash=$(shasum -a 256 "$archive" | awk '{print $1}')
fi
[[ "$actual_hash" == "$expected_hash" ]] || { printf 'Archive checksum mismatch.\n' >&2; exit 1; }

while IFS= read -r entry; do
  case "/$entry/" in *'/../'* ) printf 'Unsafe archive entry: %s\n' "$entry" >&2; exit 1 ;; esac
  [[ "$entry" != /* && ! "$entry" =~ ^[A-Za-z]: ]] || { printf 'Unsafe archive entry: %s\n' "$entry" >&2; exit 1; }
done < <(tar -tzf "$archive")
while IFS= read -r entry_type; do
  [[ "$entry_type" == - || "$entry_type" == d ]] || { printf 'Archive links and special files are not allowed.\n' >&2; exit 1; }
done < <(tar -tvzf "$archive" | awk '{print substr($1, 1, 1)}')
expanded="$temp/expanded"
mkdir -p -- "$expanded"
tar -xzf "$archive" -C "$expanded"
candidate=''
for directory in "$expanded"/*; do
  [[ -d "$directory" && -f "$directory/BUILD-INFO.json" ]] || continue
  candidate=$directory
  break
done
[[ -n "$candidate" ]] || { printf 'Archive does not contain a Bubbl marketplace root.\n' >&2; exit 1; }

read_json_value() {
  local file=$1 key=$2
  sed -nE 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$file" | head -n 1
}
build_info="$candidate/BUILD-INFO.json"
[[ "$(read_json_value "$build_info" repository)" == "$repository" ]]
[[ "$(read_json_value "$build_info" version)" == "$version" ]]
[[ "$(read_json_value "$build_info" target)" == "$target" ]]
[[ "$(read_json_value "$build_info" tag)" == "$tag" ]]
[[ "$(read_json_value "$build_info" commit)" == "$source_commit" ]]
[[ "$(read_json_value "$candidate/plugins/bubbl/.codex-plugin/plugin.json" version)" == "$version" ]]
grep -Fq '"name": "bubbl-release"' "$candidate/.agents/plugins/marketplace.json"
grep -Fq '"path": "./plugins/bubbl"' "$candidate/.agents/plugins/marketplace.json"

mkdir -p -- "$(dirname -- "$install_root")"
install_parent=$(cd -- "$(dirname -- "$install_root")" && pwd)
install_full="$install_parent/$(basename -- "$install_root")"
marketplace_json=$(codex plugin marketplace list --json)
existing_root=$(printf '%s\n' "$marketplace_json" | tr ',' '\n' | awk '
  /"name":[[:space:]]*"bubbl-release"/ { found=1; next }
  found && /"root":/ { sub(/^.*"root":[[:space:]]*"/, ""); sub(/".*$/, ""); print; exit }
')
if [[ -n "$existing_root" ]]; then
  existing_parent=$(cd -- "$(dirname -- "$existing_root")" && pwd)
  existing_full="$existing_parent/$(basename -- "$existing_root")"
  [[ "$existing_full" == "$install_full" ]] || { printf "Marketplace '%s' already points to %s.\n" "$marketplace" "$existing_root" >&2; exit 1; }
fi

incoming="$install_parent/.bubbl-incoming-$$"
previous="$install_parent/.bubbl-previous-$$"
mkdir -- "$incoming"
cp -R -- "$candidate/." "$incoming/"
had_previous=0
[[ ! -e "$install_full" ]] || { mv -- "$install_full" "$previous"; had_previous=1; }
mv -- "$incoming" "$install_full"
incoming=''
if ! { [[ -n "$existing_root" ]] || codex plugin marketplace add "$install_full"; } || ! codex plugin add "bubbl@$marketplace"; then
  rm -rf -- "$install_full"
  if ((had_previous)); then
    mv -- "$previous" "$install_full"
    codex plugin add "bubbl@$marketplace" >/dev/null 2>&1 || true
  elif [[ -z "$existing_root" ]]; then
    codex plugin marketplace remove "$marketplace" >/dev/null 2>&1 || true
  fi
  printf 'Codex plugin installation failed; the previous marketplace was restored.\n' >&2
  exit 1
fi
[[ ! -e "$previous" ]] || rm -rf -- "$previous"
if ((strict)); then verification='attestation-verified'; else verification='checksum-verified immutable'; fi
printf 'Bubbl %s installed from %s release %s (%s).\n' "$version" "$verification" "$tag" "$source_commit"
printf 'Open /hooks, inspect and trust the Bubbl UserPromptSubmit hook, then start a new task.\n'
