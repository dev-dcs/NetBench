#!/usr/bin/env bash
# pack.sh - build the flashable NetBench zip. Fetches the Tailscale and EasyTier
# static arm64 binaries (pinned + checksummed), stages them into system/bin, and
# zips the module. No compiler needed - both are prebuilt.
#
#   ./pack.sh               full build -> out/NetBench-v<ver>.zip
#   ./pack.sh --tools-only  stage system/bin, do not zip
# @Dev_DcS
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd); cd "$ROOT"
. ./prebuilts.conf

MOD=$ROOT/module
BIN=$MOD/system/bin
CACHE=$ROOT/.cache
OUT=$ROOT/out
ZIP=1
[ "${1:-}" = --tools-only ] && ZIP=0

mkdir -p "$BIN" "$CACHE" "$OUT"
say() { printf '>> %s\n' "$*" >&2; }
die() { printf 'xx %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }
verify() { [ "$(sha "$1")" = "$2" ] || die "checksum mismatch for ${1##*/}"; }
elf_ok() { [ "$(od -An -tx1 -N4 "$1" | tr -d ' \n')" = 7f454c46 ] || die "${1##*/} is not ELF"; }

# ---- Tailscale ----------------------------------------------------------------
tgz="$CACHE/tailscale_${TAILSCALE_VER}_arm64.tgz"
[ -f "$tgz" ] && sha "$tgz" | grep -q "^$TAILSCALE_SHA$" || \
  curl -fSL --retry 3 -o "$tgz" "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VER}_arm64.tgz"
verify "$tgz" "$TAILSCALE_SHA"
rm -rf "$CACHE/ts"; mkdir -p "$CACHE/ts"; tar xzf "$tgz" -C "$CACHE/ts" --strip-components=1
install -m 0755 "$CACHE/ts/tailscale"  "$BIN/tailscale"
install -m 0755 "$CACHE/ts/tailscaled" "$BIN/tailscaled"
elf_ok "$BIN/tailscale"; elf_ok "$BIN/tailscaled"; say "staged tailscale $TAILSCALE_VER"

# ---- EasyTier -----------------------------------------------------------------
etz="$CACHE/easytier-${EASYTIER_VER}-aarch64.zip"
[ -f "$etz" ] && sha "$etz" | grep -q "^$EASYTIER_SHA$" || \
  curl -fSL --retry 3 -o "$etz" "https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VER}/easytier-linux-aarch64-${EASYTIER_VER}.zip"
verify "$etz" "$EASYTIER_SHA"
rm -rf "$CACHE/et"; mkdir -p "$CACHE/et"; unzip -qo "$etz" -d "$CACHE/et"
d=$(dirname "$(find "$CACHE/et" -name easytier-core | head -n1)")
install -m 0755 "$d/easytier-core" "$BIN/easytier-core"
install -m 0755 "$d/easytier-cli"  "$BIN/easytier-cli"
elf_ok "$BIN/easytier-core"; say "staged easytier $EASYTIER_VER"

# ---- assemble -----------------------------------------------------------------
ver=$(sed -n 's/^version=//p' "$MOD/module.prop")
[ "$ZIP" = 1 ] || { say "tools staged (no zip)"; exit 0; }
zipout="$OUT/NetBench-$ver.zip"; rm -f "$zipout"
find "$MOD" -name '*.sh' -exec sed -i 's/\r$//' {} +
( cd "$MOD" && zip -qr9X "$zipout" . -x '.*' )
say "built $zipout ($(( $(stat -c %s "$zipout") / 1024 / 1024 )) MiB)"
