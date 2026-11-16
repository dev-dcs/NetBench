#!/system/bin/sh
# update-check - asks the repo's update.json whether a newer module is out.
# Prints a line, or JSON for the WebUI with --json. @Dev_DcS
MODDIR=${MODDIR:-$(cd "${0%/*}/.." 2>/dev/null && pwd)}
PROP=$MODDIR/module.prop
STATE=/data/adb/netbench/update.state

url=$(sed -n 's/^updateJson=//p' "$PROP")
cur=$(sed -n 's/^versionCode=//p' "$PROP")
curname=$(sed -n 's/^version=//p' "$PROP")

fetch() {
  command -v curl >/dev/null 2>&1 && { curl -fsSL -m 20 "$1" 2>/dev/null && return 0; }
  for bb in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
    [ -x "$bb" ] && "$bb" wget -q -T 20 -O - "$1" 2>/dev/null && return 0
  done
  return 1
}

json=$(fetch "$url") || { echo "could not reach update server"; exit 0; }
get() { printf '%s' "$json" | sed -n "s/.*\"$1\" *: *\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" | head -n1; }
rcode=$(get versionCode); rname=$(get version); rzip=$(get zipUrl)
[ -n "$rcode" ] || { echo "no versionCode from server"; exit 0; }

[ "$rcode" -gt "${cur:-0}" ] 2>/dev/null && avail=1 || avail=0
{ echo "available=$avail"; echo "latest=$rname"; echo "zip=$rzip"; echo "checkedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "$STATE" 2>/dev/null

case ${1:-} in
  --json) printf '{"available":%s,"current":"%s","latest":"%s","zipUrl":"%s"}\n' "$avail" "$curname" "$rname" "$rzip" ;;
  --boot)
    if [ "$avail" = 1 ]; then
      s=$(date +%Y%m%d); [ "$(cat /data/adb/netbench/.notified 2>/dev/null)" = "$s" ] && exit 0
      echo "$s" > /data/adb/netbench/.notified
      cmd notification post -S bigtext -t "NetBench $rname" netbench "A newer module is available" >/dev/null 2>&1 || true
    fi ;;
  *) [ "$avail" = 1 ] && echo "update available: $rname (you have $curname)" || echo "up to date ($curname)" ;;
esac
