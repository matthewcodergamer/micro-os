# Misty Performance Engine

## The hard boundary

Misty OS runs Ubuntu inside PRoot. PRoot is a `ptrace`-based user-space
interpreter: it translates path names and syscall arguments and nothing else. It
does **not** own the phone's kernel, ZRAM block device, scheduler, GPU or memory
cgroup.

Consequences, stated plainly:

- The app cannot enable `CONFIG_KCOMPRESSD`, change ZRAM writeback, set
  `BDI_CAP_STABLE_WRITES` or touch `dmemcg-booster`. Those are kernel/ROM
  features. A patch series cannot be "applied" from Dart, and writing to
  `/sys/block/zram0/` from an Android app would either fail or destabilise the
  device.
- Android's `lmkd` decides when to kill processes. Misty OS can only reduce its
  own footprint before that happens.

The kernel track in the engineering brief is therefore documented as an
**optional advanced track** for custom-ROM users. It is not shipped, not faked,
and not simulated in the UI.

## What is implemented (Phase 1: measure first)

`lib/services/performance_monitor.dart` reads only sources an unrooted app can
read, and never invents a value:

| Source | Used for | When hidden by the OS |
| --- | --- | --- |
| `/proc/meminfo` | RAM used/available, cached, anon, swap | reported `unavailable` |
| `/proc/stat` | CPU utilisation, sampled twice 240 ms apart | reported `unavailable` |
| `/proc/pressure/{cpu,memory,io}` | PSI stall averages (Linux 5.2+) | reported `unavailable` |
| `/sys/block/zram0/*` | ZRAM compression ratio and compressed size | reported `unavailable` |
| `/proc/<pid>/status` | top processes by RSS | best-effort; most Android builds hide other UIDs |
| `SchedulerBinding` frame timings | UI frame p50/p95/p99 | `no samples yet` |

The UI is **Settings → Performance**. It shows the dominant bottleneck
(memory pressure → memory saturation → CPU saturation → frame pacing → swap
activity), and every card labels missing data honestly instead of showing a
placeholder percentage.

Telemetry is page-scoped: the monitor starts in `initState`, stops in `dispose`,
and costs nothing when the page is closed. Parsing helpers (`parseMeminfo`,
`parseProcStat`, `parsePressureSomeAvg10`, `percentile`,
`zramCompressionRatio`, `pressureBand`, `describeBottleneck`) are pure functions
covered by `test/performance_monitor_test.dart`.

## Guest-side tuning that is implemented

- Chromium already runs with `--process-per-site`, `--disable-dev-shm-usage`,
  a 512 MB JS heap cap, 64 MB disk cache and 16 MB media cache.
- Added in this pass: `--disable-crash-reporter` and `--disable-low-res-tiling`.
  `--disable-site-isolation-trials` was **not** added: it saves 9–11% memory by
  weakening site isolation, which is a security regression on a browser that
  handles logins.
- The rootfs is still shipped as a single `zstd` archive and extracted with an
  8 MiB streaming buffer, so extraction never materialises the 1.28 GB image in
  RAM.

## What is not implemented, and why

| Brief item | Status |
| --- | --- |
| `kcompressd`, async ZRAM writeback, multi-page batching, `BDI_CAP_STABLE_WRITES` | Out of reach from PRoot. Optional advanced track. |
| `dmemcg-booster` / VRAM foreground priority | Out of reach (kernel + systemd on the host). No Vulkan/VRAM ownership inside PRoot. |
| Custom Chromium build with `is_high_end_android` | The guest uses the distro Chromium build. Rebuilding Chromium in CI would add hours and hundreds of GB for a flag set that targets Android WebView, not a PRoot X11 browser. |
| SearXNG instance | Not shipped. It would need a guest service and a network policy decision; adding a dead search box would be worse than none. |
| Termux-X11 instead of noVNC | Genuinely the right long-term direction, and the highest-leverage rendering change. It is a separate project-sized migration (a second Android process plus a guest X server); it is not a refactor of the existing VNC pipeline. |

## Measurement protocol for the next phase

1. Open Settings → Performance on the target device with a long-lived terminal.
2. Record p95 frame time and PSI memory stall before and after each change.
3. Any claim of improvement must cite a before/after pair from that page, not an
   estimate.
