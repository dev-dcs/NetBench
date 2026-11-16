#!/system/bin/sh
# NetBench - post-fs-data: just make sure our state dir exists. Firewall and
# daemons wait for the network, so they run from service.sh, not here.
mkdir -p /data/adb/netbench 2>/dev/null
chmod 0700 /data/adb/netbench 2>/dev/null
