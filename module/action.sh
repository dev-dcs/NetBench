#!/system/bin/sh
# Action button in the root manager - quick status.
MODDIR=${0%/*}
MODDIR=$MODDIR sh "$MODDIR/libexec/netctl.sh" status
