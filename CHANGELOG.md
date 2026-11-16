## v1.0.0

First release.

- Per-app internet blocking through NetBench's own iptables chain (NETBENCH_OUT),
  so it never clashes with an ad-blocker, InviZible or Sentry.
- TCP tuning: pick a congestion control (BBR, cubic, …) and default qdisc (cake,
  fq_codel, …); re-applied on boot.
- ADB over Wi-Fi, with a clear warning and a one-tap off.
- Tailscale and EasyTier mesh VPNs (static arm64 binaries), start/stop and autostart.
- A light VoLTE/VoWiFi override toggle (device dependent; no radio identities touched).
- WebUI for all of it, plus updateJson + an opt-in boot update check.
- Weekly workflow rolls Tailscale and EasyTier to upstream and releases on its own.
