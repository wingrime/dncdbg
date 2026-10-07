#!/usr/bin/env bash
#
# Re-vendor the native subset of dotnet/diagnostics that is used to build
# libdbgshim (dbgshim target) into third-party/diagnostics and apply dncdbg's
# local patches.
#
# Usage:
#   tools/update-diagnostics.sh [<ref>] [--repo-root <dir>]
#
#   <ref>   git ref (commit SHA, tag or branch) of dotnet/diagnostics.
#           Defaults to DEFAULT_REF below.
#
# The script is intentionally fail-fast: it replaces the vendored sources with
# the requested revision and then applies every patch from
# third-party/diagnostics/patches via `git apply`, so a patch that no longer
# applies aborts the run instead of silently producing a stale build.

set -euo pipefail

DIAGNOSTICS_REPO="dotnet/diagnostics"

# Pinned revision used when no explicit ref is passed. Bump it together with
# the patch set and THIRD-PARTY-NOTICES.md.
DEFAULT_REF="3359d7c23d7e436ac96d3ea760eca89a70ee4e81"

usage() {
  cat <<EOF
Re-vendor the native subset of ${DIAGNOSTICS_REPO} that is used to build
libdbgshim (dbgshim target) into third-party/diagnostics and apply dncdbg's
local patches.

Usage:
  tools/update-diagnostics.sh [<ref>] [--repo-root <dir>]

  <ref>   git ref (commit SHA, tag or branch) of ${DIAGNOSTICS_REPO}.
          Default: ${DEFAULT_REF}

  --repo-root <dir>   dncdbg repository root (defaults to the script's parent).

The script is fail-fast: it replaces the vendored sources with the requested
revision and then applies every patch from third-party/diagnostics/patches via
'git apply', so a patch that no longer applies aborts the run instead of
silently producing a stale build.
EOF
}

REF="$DEFAULT_REF"
REPO_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      [ $# -ge 2 ] || { echo "error: --repo-root requires an argument" >&2; exit 2; }
      REPO_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      REF="$1"
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

DEST="$REPO_ROOT/third-party/diagnostics"
PATCH_DIR="$DEST/patches"

[ -d "$DEST" ]      || { echo "error: $DEST not found" >&2; exit 1; }
[ -d "$PATCH_DIR" ] || { echo "error: $PATCH_DIR not found" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dncdbg-diagnostics.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading ${DIAGNOSTICS_REPO}@${REF}"
curl -fsSL -o "$WORK/src.tar.gz" \
  "https://codeload.github.com/${DIAGNOSTICS_REPO}/tar.gz/${REF}"

tar -xzf "$WORK/src.tar.gz" -C "$WORK"
SRC="$(find "$WORK" -maxdepth 1 -mindepth 1 -type d -name 'diagnostics-*' | head -n1)"
[ -n "$SRC" ] || { echo "error: extracted diagnostics tree not found" >&2; exit 1; }

echo "==> Replacing vendored native subset in $DEST"
# Drop the previous upstream-derived sources but keep patches/ and artifacts/
# (artifacts/obj contains the checked-in generated version files).
rm -rf "$DEST/eng" "$DEST/src"
rm -f  "$DEST/CMakeLists.txt" "$DEST/LICENSE.TXT" "$DEST/README.md"
rm -f  "$DEST"/v[0-9]* "$DEST"/diagnostics-*

mkdir -p "$DEST/eng" "$DEST/src"
cp "$SRC/CMakeLists.txt" "$SRC/LICENSE.TXT" "$SRC/README.md" "$DEST/"
cp -R "$SRC/eng/native" "$DEST/eng/native"
rm -rf "$DEST/eng/native/ijw"
cp "$SRC/src/CMakeLists.txt" "$DEST/src/CMakeLists.txt"
cp -R "$SRC/src/dbgshim" "$DEST/src/dbgshim"
cp -R "$SRC/src/inc" "$DEST/src/inc"
cp -R "$SRC/src/shared" "$DEST/src/shared"
# Subdirectories only needed by SOS.
rm -rf "$DEST/src/shared/gcdump" "$DEST/src/shared/gcinfo" \
       "$DEST/src/shared/hosts" "$DEST/src/shared/vm"

echo "==> Applying dncdbg patches"
shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
[ ${#patches[@]} -gt 0 ] || { echo "error: no patches found in $PATCH_DIR" >&2; exit 1; }
for p in "${patches[@]}"; do
  echo "    - $(basename "$p")"
  # Run from the repository root and prepend the vendored directory: `git apply`
  # resolves patch paths against the repository root and silently skips paths
  # that fall outside the current directory.
  git -C "$REPO_ROOT" apply -p1 --directory=third-party/diagnostics "$p"
done

# Refresh the generated version files so the built library reports the
# diagnostics revision it was actually built from instead of the version of the
# vendored baseline. Upstream normally regenerates these in eng/native; the
# dncdbg build consumes the checked-in copies under artifacts/obj directly.
VERSION_PREFIX="$(sed -n 's:.*<VersionPrefix>\(.*\)</VersionPrefix>.*:\1:p' "$SRC/eng/Versions.props" | head -n1)"
VERSION_PREFIX="${VERSION_PREFIX:-0.0.0}"
COMMIT="$(basename "$SRC")"
if [[ "$COMMIT" =~ ^diagnostics-([0-9a-f]{40})$ ]]; then
  COMMIT="${BASH_REMATCH[1]}"
else
  COMMIT="$REF"
fi
NUM_VERSION="$(printf '%s' "$VERSION_PREFIX" | awk -F. '{printf "%d,%d,%d,0", $1, $2, $3}')"

printf 'char sccsid[] __attribute__((used)) = "@(#)Version %s @Commit: %s";\n' \
  "$VERSION_PREFIX" "$COMMIT" > "$DEST/artifacts/obj/_version.c"

version_header="$DEST/artifacts/obj/_version.h"
if [ -f "$version_header" ]; then
  tmp="$(mktemp)"
  sed \
    -e "s|^#define VER_PRODUCTVERSION .*|#define VER_PRODUCTVERSION          ${NUM_VERSION}|" \
    -e "s|^#define VER_PRODUCTVERSION_STR .*|#define VER_PRODUCTVERSION_STR      \"${VERSION_PREFIX} @Commit: ${COMMIT}\"|" \
    -e "s|^#define VER_FILEVERSION .*|#define VER_FILEVERSION             ${NUM_VERSION}|" \
    -e "s|^#define VER_FILEVERSION_STR .*|#define VER_FILEVERSION_STR         \"${NUM_VERSION} @Commit: ${COMMIT}\"|" \
    "$version_header" > "$tmp"
  mv "$tmp" "$version_header"
fi

# Version marker: keep the human readable tag when a tag was requested,
# otherwise record the (possibly abbreviated) commit sha.
if [[ "$REF" =~ ^v[0-9] ]]; then
  MARKER="$REF"
else
  MARKER="diagnostics-$(printf '%s' "$REF" | cut -c1-12)"
fi
: > "$DEST/$MARKER"
echo "==> Version marker: third-party/diagnostics/$MARKER"
echo "==> Done. Bump the pinned ref / THIRD-PARTY-NOTICES.md when updating."
