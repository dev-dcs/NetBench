#!/system/bin/sh
# netctl - the engine behind NetBench. Per-app internet blocking, TCP tuning,
# ADB over Wi-Fi, a VoLTE/VoWiFi toggle, and start/stop for the Tailscale and
# EasyTier daemons. Runs as root. POSIX sh (mksh-safe).
# @Dev_DcS

MODDIR=${MODDIR:-$(cd "${0%/*}/.." 2>/dev/null && pwd)}
export PATH="$MODDIR/system/bin:/system/bin:/system/xbin:$PATH"

DATA=/data/adb/netbench
CONF=$DATA/netbench.conf
BLOCKS=$DATA/blocks.list        # one uid per line
LOG=$DATA/netbench.log
# our own chain name, so we never collide with InviZible, Re-Malwack, Sentry, etc.
CHAIN=NETBENCH_OUT
TS_SOCK=$DATA/tailscaled.sock
TS_STATE=$DATA/tailscaled.state

mkdir -p "$DATA" 2>/dev/null
say() { printf '%s\n' "$*"; }
err() { printf 'x %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }
log() { printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null; }
need_root() { [ "$(id -u)" = 0 ] || die "run as root"; }

getconf() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -n1; }
setconf() {
  mkdir -p "$DATA"
  if grep -q "^$1=" "$CONF" 2>/dev/null; then sed -i "s|^$1=.*|$1=$2|" "$CONF"; else echo "$1=$2" >>"$CONF"; fi
}

# ---- per-app internet block ---------------------------------------------------
# A dedicated chain hooked off OUTPUT. We only ever touch this chain, so other
# firewall modules are untouched. Matching is by app UID via owner match.

both() { iptables "$@"; ip6tables "$@"; }

chain_init() {
  for ipt in iptables ip6tables; do
    $ipt -nL "$CHAIN" >/dev/null 2>&1 || $ipt -N "$CHAIN" 2>/dev/null
    # hook it off OUTPUT exactly once
    $ipt -C OUTPUT -j "$CHAIN" 2>/dev/null || $ipt -I OUTPUT -j "$CHAIN" 2>/dev/null
  done
}

chain_teardown() {
  for ipt in iptables ip6tables; do
    $ipt -D OUTPUT -j "$CHAIN" 2>/dev/null
    $ipt -F "$CHAIN" 2>/dev/null
    $ipt -X "$CHAIN" 2>/dev/null
  done
}

uid_of() {
  # accept a bare uid, or resolve a package name to its uid
  case $1 in
    ''|*[!0-9A-Za-z._]*) return 1 ;;
    *[!0-9]*) ;;                     # has letters -> package
    *) printf '%s' "$1"; return 0 ;; # all digits -> already a uid
  esac
  u=$(pm list packages -U 2>/dev/null | sed -n "s/^package:$1 uid://p" | head -n1)
  [ -n "$u" ] || u=$(stat -c %u "/data/data/$1" 2>/dev/null)
  [ -n "$u" ] && { printf '%s' "$u"; return 0; }
  return 1
}

block_rule() { both "$1" "$CHAIN" -m owner --uid-owner "$2" -j REJECT 2>/dev/null; }

cmd_block() {
  need_root
  case ${1:-list} in
    list)
      [ -s "$BLOCKS" ] || { say "(nothing blocked)"; return 0; }
      while read -r u; do [ -n "$u" ] && say "uid $u"; done < "$BLOCKS"
      ;;
    add)
      shift; chain_init
      for a in "$@"; do
        u=$(uid_of "$a") || { err "can't resolve '$a'"; continue; }
        grep -qx "$u" "$BLOCKS" 2>/dev/null && { say "$a already blocked"; continue; }
        block_rule -A "$u" && { echo "$u" >>"$BLOCKS"; say "blocked $a (uid $u)"; log "block $a uid $u"; }
      done
      ;;
    rm)
      shift
      for a in "$@"; do
        u=$(uid_of "$a") || u=$a
        block_rule -D "$u" 2>/dev/null
        [ -f "$BLOCKS" ] && grep -vx "$u" "$BLOCKS" > "$BLOCKS.t" && mv -f "$BLOCKS.t" "$BLOCKS"
        say "unblocked $a (uid $u)"
      done
      ;;
    clear)
      chain_teardown; : > "$BLOCKS"; say "all app blocks cleared"; log "block clear"
      ;;
    *) die "block list|add|rm|clear" ;;
  esac
}

apply_blocks() {
  [ -s "$BLOCKS" ] || return 0
  chain_init
  while read -r u; do
    case $u in ''|*[!0-9]*) continue ;; esac
    both -C "$CHAIN" -m owner --uid-owner "$u" -j REJECT 2>/dev/null || block_rule -A "$u"
  done < "$BLOCKS"
}

# ---- TCP tuning ---------------------------------------------------------------
cmd_tcp() {
  case ${1:-show} in
    show)
      say "available: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)"
      say "current  : $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
      say "qdisc    : $(cat /proc/sys/net/core/default_qdisc 2>/dev/null)"
      ;;
    set)
      need_root
      cc=$2 qd=$3
      [ -n "$cc" ] || die "tcp set <cc> [qdisc]"
      if ! grep -qw "$cc" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        die "'$cc' not available (have: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control))"
      fi
      echo "$cc" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null && setconf TCP_CC "$cc"
      if [ -n "$qd" ]; then echo "$qd" > /proc/sys/net/core/default_qdisc 2>/dev/null && setconf TCP_QDISC "$qd"; fi
      say "tcp: cc=$cc${qd:+ qdisc=$qd}"; log "tcp set $cc $qd"
      ;;
    reset)
      need_root
      sed -i '/^TCP_CC=/d;/^TCP_QDISC=/d' "$CONF" 2>/dev/null
      say "tcp settings cleared (unchanged until reboot)"
      ;;
    *) die "tcp show|set|reset" ;;
  esac
}

apply_tcp() {
  cc=$(getconf TCP_CC) qd=$(getconf TCP_QDISC)
  [ -n "$cc" ] && grep -qw "$cc" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null && echo "$cc" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
  [ -n "$qd" ] && echo "$qd" > /proc/sys/net/core/default_qdisc 2>/dev/null
}

# ---- ADB over Wi-Fi -----------------------------------------------------------
cmd_adb() {
  need_root
  case ${1:-status} in
    on)
      port=${2:-5555}
      case $port in ''|*[!0-9]*) die "port must be a number" ;; esac
      setprop service.adb.tcp.port "$port"
      setprop ctl.restart adbd 2>/dev/null || { stop adbd; start adbd; }
      setconf ADB_TCP "$port"
      ip=$(ip route get 1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -n1)
      say "adb over Wi-Fi on, port $port${ip:+ — connect: adb connect $ip:$port}"
      say "note: anyone on your network can reach adb now. Turn it off when done."
      log "adb tcp on $port"
      ;;
    off)
      setprop service.adb.tcp.port -1
      setprop ctl.restart adbd 2>/dev/null || { stop adbd; start adbd; }
      sed -i '/^ADB_TCP=/d' "$CONF" 2>/dev/null
      say "adb over Wi-Fi off"; log "adb tcp off"
      ;;
    status)
      p=$(getprop service.adb.tcp.port 2>/dev/null)
      case $p in ''|-1|0) say "off" ;; *) say "on (port $p)" ;; esac
      ;;
    *) die "adb on|off|status" ;;
  esac
}

apply_adb() {
  port=$(getconf ADB_TCP); [ -n "$port" ] || return 0
  setprop service.adb.tcp.port "$port"
  setprop ctl.restart adbd 2>/dev/null || { stop adbd; start adbd; }
}

# ---- VoLTE / VoWiFi toggle ----------------------------------------------------
# A light switch over the common IMS override props. Device dependent - on some
# ROMs it does nothing, on others it turns VoLTE/VoWiFi on. resetprop (Magisk)
# makes it stick; plain setprop otherwise. No radio identities are touched.
SETP=setprop
command -v resetprop >/dev/null 2>&1 && SETP=resetprop
IMS_PROPS="persist.dbg.volte_avail_ovr persist.dbg.vt_avail_ovr persist.dbg.wfc_avail_ovr persist.dbg.allow_volte"

cmd_ims() {
  need_root
  case ${1:-status} in
    enable)  for p in $IMS_PROPS; do $SETP "$p" 1 2>/dev/null; done; setconf IMS 1
             say "VoLTE/VoWiFi overrides on (reboot or toggle airplane mode to apply)"; log "ims on" ;;
    disable) for p in $IMS_PROPS; do $SETP "$p" 0 2>/dev/null; done; sed -i '/^IMS=/d' "$CONF" 2>/dev/null
             say "VoLTE/VoWiFi overrides off"; log "ims off" ;;
    status)  say "IMS override: $([ "$(getconf IMS)" = 1 ] && echo on || echo off)"
             for p in $IMS_PROPS; do say "$p=$(getprop "$p" 2>/dev/null)"; done ;;
    *) die "ims enable|disable|status" ;;
  esac
}
apply_ims() { [ "$(getconf IMS)" = 1 ] && for p in $IMS_PROPS; do $SETP "$p" 1 2>/dev/null; done; }

# ---- Tailscale ----------------------------------------------------------------
TS="tailscale --socket=$TS_SOCK"
cmd_tailscale() {
  command -v tailscaled >/dev/null 2>&1 || die "tailscaled not in this build"
  case ${1:-status} in
    start)
      pgrep -f "tailscaled.*$TS_SOCK" >/dev/null 2>&1 && { say "already running"; return 0; }
      need_root
      tailscaled --state="$TS_STATE" --socket="$TS_SOCK" --tun=tailscale0 >>"$LOG" 2>&1 &
      setconf TS_AUTOSTART 1
      say "tailscaled started — run: netctl tailscale up   to log in"
      ;;
    stop) need_root; pkill -f "tailscaled.*$TS_SOCK" 2>/dev/null; sed -i '/^TS_AUTOSTART=/d' "$CONF" 2>/dev/null; say "tailscaled stopped" ;;
    up)   shift; need_root; $TS up "$@" ;;
    down) need_root; $TS down ;;
    status|ip) $TS "$1" 2>/dev/null || say "tailscaled not running" ;;
    *) need_root; $TS "$@" ;;
  esac
}

# ---- EasyTier -----------------------------------------------------------------
ET_PID=$DATA/easytier.pid
cmd_easytier() {
  command -v easytier-core >/dev/null 2>&1 || die "easytier-core not in this build"
  case ${1:-status} in
    start)
      shift; need_root
      [ -f "$ET_PID" ] && kill -0 "$(cat "$ET_PID")" 2>/dev/null && { say "already running"; return 0; }
      # remaining args are passed to easytier-core (e.g. --network-name x --network-secret y)
      [ $# -gt 0 ] && setconf ET_ARGS "$*"
      args=$(getconf ET_ARGS)
      # shellcheck disable=SC2086
      easytier-core $args >>"$LOG" 2>&1 &
      echo $! > "$ET_PID"; setconf ET_AUTOSTART 1
      say "easytier-core started (${args:-no args set})"
      ;;
    stop) need_root; [ -f "$ET_PID" ] && kill "$(cat "$ET_PID")" 2>/dev/null; rm -f "$ET_PID"
          sed -i '/^ET_AUTOSTART=/d' "$CONF" 2>/dev/null; say "easytier stopped" ;;
    status)
      if [ -f "$ET_PID" ] && kill -0 "$(cat "$ET_PID")" 2>/dev/null; then
        say "running (pid $(cat "$ET_PID"))"; easytier-cli peer 2>/dev/null
      else say "stopped"; fi ;;
    cli) shift; easytier-cli "$@" ;;
    *) die "easytier start|stop|status|cli" ;;
  esac
}

# ---- boot ---------------------------------------------------------------------
cmd_apply_boot() {
  need_root
  apply_tcp
  apply_blocks
  apply_adb
  apply_ims
  [ "$(getconf TS_AUTOSTART)" = 1 ] && cmd_tailscale start >/dev/null 2>&1
  [ "$(getconf ET_AUTOSTART)" = 1 ] && cmd_easytier start >/dev/null 2>&1
  log "apply-boot done"
}

cmd_status() {
  say "== NetBench =="
  say "blocked apps: $([ -f "$BLOCKS" ] && grep -c . "$BLOCKS" || echo 0)"
  say "tcp cc: $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)  qdisc: $(cat /proc/sys/net/core/default_qdisc 2>/dev/null)"
  p=$(getprop service.adb.tcp.port 2>/dev/null); case $p in ''|-1|0) say "adb-wifi: off" ;; *) say "adb-wifi: on ($p)" ;; esac
  say "ims override: $([ "$(getconf IMS)" = 1 ] && echo on || echo off)"
  command -v tailscaled >/dev/null 2>&1 && say "tailscale: $(pgrep -f "tailscaled.*$TS_SOCK" >/dev/null 2>&1 && echo running || echo stopped)"
  command -v easytier-core >/dev/null 2>&1 && say "easytier: $([ -f "$ET_PID" ] && kill -0 "$(cat "$ET_PID")" 2>/dev/null && echo running || echo stopped)"
}

case ${1:-status} in
  status) cmd_status ;;
  block) shift; cmd_block "$@" ;;
  tcp) shift; cmd_tcp "$@" ;;
  adb) shift; cmd_adb "$@" ;;
  ims) shift; cmd_ims "$@" ;;
  tailscale|ts) shift; cmd_tailscale "$@" ;;
  easytier|et) shift; cmd_easytier "$@" ;;
  apply-boot) cmd_apply_boot ;;
  *) die "netctl status|block|tcp|adb|ims|tailscale|easytier|apply-boot" ;;
esac
