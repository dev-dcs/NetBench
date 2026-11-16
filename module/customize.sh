#!/system/bin/sh
# NetBench - install-time setup. POSIX sh.
SKIPUNZIP=0

ui_print "- NetBench $(sed -n 's/^version=//p' "$MODPATH/module.prop")"
case "$ARCH" in
  arm64|x64) ui_print "- Arch: $ARCH" ;;
  *) abort "! arm64 or x86_64 only (got '$ARCH')" ;;
esac

set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/libexec" 0 0 0755 0755
for s in post-fs-data.sh service.sh uninstall.sh action.sh; do
  [ -f "$MODPATH/$s" ] && set_perm "$MODPATH/$s" 0 0 0755
done

have=""
for t in tailscale tailscaled easytier-core easytier-cli; do
  [ -e "$MODPATH/system/bin/$t" ] && have="$have $t"
done
ui_print "- VPN tools:${have:- (none bundled)}"

mkdir -p /data/adb/netbench
chmod 0700 /data/adb/netbench 2>/dev/null

ui_print "- Uses its own iptables chain (NETBENCH_OUT); it won't fight your"
ui_print "  ad-blocker or InviZible."
ui_print "- Done. Reboot, then open the WebUI."
