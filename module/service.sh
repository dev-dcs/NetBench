#!/system/bin/sh
# NetBench - late_start service: once the system is up, re-apply the saved
# network setup (blocks, TCP, adb-over-wifi, IMS, and any autostart daemons).
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
sleep 8
MODDIR=$MODDIR sh "$MODDIR/libexec/netctl.sh" apply-boot >/dev/null 2>&1

# opt-in update check (writes /data/adb/netbench/update.state)
if grep -q '^update_check=1' /data/adb/netbench/netbench.conf 2>/dev/null && [ -f "$MODDIR/libexec/update-check.sh" ]; then
  MODDIR=$MODDIR sh "$MODDIR/libexec/update-check.sh" --boot >/dev/null 2>&1 &
fi
