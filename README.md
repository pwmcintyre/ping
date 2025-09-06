# ping_stats — Latency & Packet-Loss Probe for Video Calls

A tiny, portable Bash wrapper around `ping` that collects timestamped RTT samples and summarizes **min / p50 / p90 / p99 / max** plus **packet loss**. Designed to help diagnose “you keep cutting out” issues during Google Meet / Teams by comparing two devices side-by-side over \~10 minutes.

Works on **macOS** and **Linux** (including **Ubuntu via WSL** on Windows). No root required (at 1s intervals).

---

## Why this exists

Speed tests often look “fine,” yet video calls still stutter. That’s usually about **latency jitter** or **packet loss**, not bandwidth. This script:

* Pings a target host (default: `lens.meet.l.google.com`) at a fixed interval
* Logs **UTC timestamps** + RTT (ms) to CSV
* Computes **min/p50/p90/p99/max** with the nearest-rank method
* Reports **packet loss %** (counting missing replies)
* Lists timestamps for all samples **≥ p99**

Use it to run simultaneous probes from different devices (e.g., Windows desktop vs MacBook) to see if the problem is device-specific or network-wide.

---

## Quick start

1. Save the script as `ping_stats.sh` (from this repo).
2. Make it executable:

   ```bash
   chmod +x ping_stats.sh
   ```
3. Run for 10 minutes at 1 packet/second:

   ```bash
   ./ping_stats.sh lens.meet.l.google.com 600 1 pc_ping
   ```

   Produce a different `out_prefix` on each device, e.g.:

   ```bash
   ./ping_stats.sh lens.meet.l.google.com 600 1 mac_ping
   ```

**Outputs per run**

* `pc_ping.csv` – timestamped samples (`timestamp_utc,seq,rtt_ms`)
* `pc_ping.summary.txt` – stats & loss summary
* `pc_ping.p99_timestamps.txt` – timestamps for samples ≥ p99

---

## Requirements

* **macOS** or **Linux** (including **WSL Ubuntu** on Windows)
* `/usr/bin/env bash`, `ping`, `awk`, `sort`
* Internet access to the target host

> Note: macOS allows 1s intervals without sudo; intervals <1s require root on macOS. On Linux, sub-second may work unprivileged depending on sysctls, but we standardize on **1s**.

---

## Usage

```bash
./ping_stats.sh [host] [duration_seconds] [interval_seconds] [out_prefix]
```

**Defaults**

* `host` = `lens.meet.l.google.com`
* `duration_seconds` = `600` (10 minutes)
* `interval_seconds` = `1`
* `out_prefix` = `pingrun_<UTC_TIMESTAMP>`

**Examples**

```bash
# 10 minutes, 1s interval, default host
./ping_stats.sh

# 15 minutes to a different host
./ping_stats.sh 8.8.8.8 900 1 office_test

# 5 minutes to Meet, custom prefix
./ping_stats.sh lens.meet.l.google.com 300 1 livingroom
```

---

## How it works

* Sends `COUNT = duration / interval` ICMP echo requests (`ping -c COUNT -i INTERVAL host`).
* Parses successful replies (those with `time=... ms`) into a CSV with UTC timestamps.
* Sorts RTTs and computes:

  * **min / max**
  * **p50 / p90 / p99** via **nearest-rank** (index `ceil(P/100 * N)` in sorted list)
* Computes **loss %** as `100 * (sent - received) / sent`.
* Exports timestamps of any RTTs **≥ p99** to help correlate spikes with real-world events.

> **Note on timeouts:** timeouts are **counted as loss** but not included in RTT percentile math (since they have no RTT). If you prefer to treat timeouts as a large RTT (e.g., `10000 ms`) for percentile calculations, see **Advanced options** below.

---

## Interpreting the results

Open `*.summary.txt`. You’ll see something like:

```
Host: lens.meet.l.google.com
Duration (s): 600
Interval (s): 1
Sent: 600
Received: 596
Loss (%): 0.67

Latency (ms):
  min : 7.12
  p50 : 12.34
  p90 : 25.80
  p99 : 131.77
  max : 482.19

CSV: pc_ping.csv
P99 timestamps (>= 131.77 ms): pc_ping.p99_timestamps.txt
```

### What’s “normal”?

These aren’t hard rules, but for a decent home connection:

* **Loss**: 0–0.5% is typical under light load; >1% can be noticeable on calls.
* **p50**: Stable baseline (e.g., 10–40 ms depending on your ISP/route).
* **p90**: Ideally not more than \~2–3× p50.
* **p99 / max**: Occasional spikes happen, but frequent spikes into **hundreds of ms** are bad for real-time voice/video.

### Comparing devices

Run the script **simultaneously** on both devices (start within a few seconds of each other):

* If **both** show similar **loss** and **p99 spikes** → likely **Wi-Fi / router / ISP**.
* If only the **Windows desktop** shows spikes/loss while the **Mac** stays clean → likely the **desktop’s Wi-Fi adapter/driver/placement** or OS/browser.
* If both are clean but you still have call issues, look at **app-level** stats (Meet/Teams “Troubleshooting/Call Health”), CPU load, background traffic, VPN/proxy, etc.

### Using `p99_timestamps.txt`

Every timestamp listed experienced an RTT ≥ p99. Correlate these with:

* What else was happening on the network (large uploads/streaming)?
* Physical interference (microwave, cordless phone)?
* Device moves / signal changes / mesh handoffs?

---

## Running good comparisons

* Use the **same host** (`lens.meet.l.google.com`) and **same duration/interval** on both devices.
* Try to keep **line-of-sight** and **similar distance** to the AP if you’re testing device differences.
* Avoid big downloads/uploads during the test unless you’re intentionally stress-testing.

---

## Output files

* **`<prefix>.csv`**
  Columns: `timestamp_utc,seq,rtt_ms`
  Only successful replies are logged.
* **`<prefix>.summary.txt`**
  Human-readable summary: sent/received/loss + min/p50/p90/p99/max.
* **`<prefix>.p99_timestamps.txt`**
  UTC timestamps for all RTTs ≥ p99 (with the RTT value).

You can load the CSV into a spreadsheet or pandas later for charts.

---

## Advanced options

### Treat timeouts as “huge RTTs” (include in percentiles)

By default, timeouts are excluded from percentile RTT math. If you want to **include** them as, say, `10000 ms`, modify the script to:

* capture **all** sequence numbers and note misses,
* append `10000` to the RTT list for each missing seq before sorting.

> Ask if you’d like a ready-made variant; it’s a small tweak.

### Longer / shorter runs

* Increase `duration_seconds` for more confidence (e.g., `1800` for 30 minutes).
* Keep `interval_seconds=1` for easy cross-platform runs without root.

---

## Troubleshooting

* **`permission denied`**: `chmod +x ping_stats.sh`
* **`bash: ./ping_stats.sh: not found`**: Check line endings. On Windows editors, save with **LF** (Unix) endings.
* **`ping: command not found`**: Install it

  * Ubuntu/WSL: `sudo apt-get update && sudo apt-get install iputils-ping`
  * macOS: built-in
* **High loss only on one device**: Update Wi-Fi drivers (Windows), try another browser for Meet, move the antenna/device, ensure you’re on **5 GHz**, not 2.4 GHz.
* **macOS interval <1s needs root**: Stick with `1` unless you run with `sudo` (not recommended here).
* **Firewall/ICMP filtering**: Some networks/hosts rate-limit ICMP. Using `lens.meet.l.google.com` is generally fine for this purpose.

---

## FAQ

**Q: Why `lens.meet.l.google.com`?**
It’s a Meet-related Google endpoint that’s typically stable and anycasted. You can substitute `8.8.8.8` or another target if you prefer—just be consistent across devices.

**Q: Are percentiles computed correctly?**
Yes—**nearest-rank** method on sorted RTT samples: index = `ceil(P/100 * N)`.

**Q: Does packet loss invalidate the percentile stats?**
Not at all. Loss is reported separately. Percentiles summarize the distribution of **successful** samples. If you want to penalize percentiles with timeouts, use the “include timeouts” variant.

---

## Sample session

```bash
./ping_stats.sh lens.meet.l.google.com 600 1 pc_ping
# ...
# writing to: pc_ping.{csv,summary.txt,p99_timestamps.txt}

cat pc_ping.summary.txt
# Host: lens.meet.l.google.com
# Duration (s): 600
# Interval (s): 1
# Sent: 600
# Received: 596
# Loss (%): 0.67
#
# Latency (ms):
#   min : 7.12
#   p50 : 12.34
#   p90 : 25.80
#   p99 : 131.77
#   max : 482.19
#
# CSV: pc_ping.csv
# P99 timestamps (>= 131.77 ms): pc_ping.p99_timestamps.txt
```

---

## License

MIT (or your preferred license).

---

## Next steps

Once you have two `*.summary.txt` files (e.g., `pc_ping.summary.txt` and `mac_ping.summary.txt`), compare **loss** and **p99/max**. If the desktop is consistently worse, focus on its Wi-Fi adapter/driver/placement and Meet/browser settings. If both are bad, tune Wi-Fi (5 GHz, interference, mesh node placement, QoS).
