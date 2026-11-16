#!/system/bin/sh
# NetBench - uninstall: drop our firewall chain, stop the daemons, clean state.
MODDIR=${0%/*}
MODDIR=$MODDIR sh "$MODDIR/libexec/netctl.sh" block clear >/dev/null 2>&1
MODDIR=$MODDIR sh "$MODDIR/libexec/netctl.sh" tailscale stop >/dev/null 2>&1
MODDIR=$MODDIR sh "$MODDIR/libexec/netctl.sh" easytier stop >/dev/null 2>&1
# adb-over-wifi back off so it doesn't linger after removal
setprop service.adb.tcp.port -1 2>/dev/null
rm -rf /data/adb/netbench 2>/dev/null
exit 0
