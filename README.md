# NetBench

A network bench as a root module: mesh VPNs, a per-app internet switch, TCP
tuning, ADB over Wi-Fi, and a VoLTE/VoWiFi toggle — all from one WebUI.

by @Dev_DcS

- arm64, Android 13–17
- Magisk, KernelSU or APatch
- keeps to its own iptables chain, so it won't fight your ad-blocker, InviZible or Sentry

## What's inside

**Block internet per app** — pick an app (or a uid) and its traffic is rejected
through NetBench's own chain, `NETBENCH_OUT`, hooked off `OUTPUT`. Nothing else in
your firewall is touched, and every block is one tap to undo. IPv4 and IPv6 both.

**TCP tuning** — choose a congestion control (BBR and whatever else your kernel
lists) and the default qdisc (cake, fq_codel, …). Re-applied on every boot.

**ADB over Wi-Fi** — turn adb's TCP port on, get the `adb connect` line, turn it
back off when you're done. It warns you while it's on, because anyone on the
network can reach it.

**Tailscale and EasyTier** — the two mesh VPNs ship as static arm64 binaries.
Start the daemon, log in (Tailscale prints a URL), or hand EasyTier your
`--network-name` / `--network-secret`. Optional autostart on boot.

**VoLTE / VoWiFi** — a light switch over the common IMS override properties. It's
device- and carrier-dependent: on some ROMs it turns VoLTE/VoWiFi on, on others it
does nothing. No radio identities are ever written.

## WebUI

Open it from your root manager (KernelSU/APatch, or Magisk via WebUI-X / MMRL):
Status, Apps, Network, VPN, Cellular.

## netctl from a shell

    netctl status
    netctl block add com.some.app          # or a uid
    netctl block list | rm <app> | clear
    netctl tcp show | set bbr cake
    netctl adb on 5555 | off | status
    netctl tailscale start | up | stop
    netctl easytier start --network-name x --network-secret y
    netctl ims enable | disable | status

## Building

`pack.sh` fetches the pinned Tailscale and EasyTier binaries (checksummed) and
zips the module — no compiler needed.

    ./pack.sh                full build -> out/NetBench-v<ver>.zip
    ./pack.sh --tools-only   stage system/bin without zipping

CI builds on a tag. The weekly job rolls Tailscale and EasyTier forward
(`scripts/bump.sh`) and tags a release when either moved.

## Layout

    module/            the flashable module (scripts, webroot, system/bin filled at pack time)
      libexec/netctl.sh        the engine
      libexec/update-check.sh
    pack.sh            build the zip
    prebuilts.conf     pinned Tailscale + EasyTier versions and checksums
    scripts/           bump.sh, release.sh

NetBench's own code is MIT; bundled tools keep their own licenses.
