#!/usr/bin/env bash
# bump.sh - roll Tailscale and EasyTier to their latest upstream, re-fetching
# checksums. Prints a summary; exits 0 either way (the caller diffs the file).
# @Dev_DcS
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
CONF=prebuilts.conf; . ./$CONF
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

set_kv() { if grep -q "^$1=" "$CONF"; then sed -i "s|^$1=.*|$1=$2|" "$CONF"; else echo "$1=$2" >>"$CONF"; fi; }
sha_url() { curl -fsSL --retry 3 -o "$tmp/f" "$1" && sha256sum "$tmp/f" | awk '{print $1}'; }

changed=0; note() { echo "$1"; changed=1; }

# Tailscale: latest stable version + its published sha256
v=$(curl -fsSL "https://pkgs.tailscale.com/stable/?mode=json" | sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' | head -n1)
if [ -n "$v" ] && [ "$v" != "$TAILSCALE_VER" ]; then
  s=$(curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${v}_arm64.tgz.sha256" | awk '{print $1}')
  [ -n "$s" ] && { set_kv TAILSCALE_VER "$v"; set_kv TAILSCALE_SHA "$s"; note "tailscale $TAILSCALE_VER -> $v"; }
fi

# EasyTier: latest release tag, sha of the aarch64 zip
t=$(curl -fsSL -H 'Accept: application/vnd.github+json' ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} \
      "https://api.github.com/repos/EasyTier/EasyTier/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
if [ -n "$t" ] && [ "$t" != "$EASYTIER_VER" ]; then
  if s=$(sha_url "https://github.com/EasyTier/EasyTier/releases/download/$t/easytier-linux-aarch64-$t.zip"); then
    set_kv EASYTIER_VER "$t"; set_kv EASYTIER_SHA "$s"; note "easytier $EASYTIER_VER -> $t"
  fi
fi

[ "$changed" = 1 ] && echo "prebuilts.conf updated" || echo "nothing to bump"
exit 0
