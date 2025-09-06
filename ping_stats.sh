#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./ping_stats.sh [host] [duration_seconds] [interval_seconds] [out_prefix]
# Defaults:
#   host=lens.meet.l.google.com
#   duration_seconds=600  (10 minutes)
#   interval_seconds=1
#   out_prefix=pingrun_$(date -u +%Y%m%dT%H%M%SZ)

HOST="${1:-lens.meet.l.google.com}"
DURATION="${2:-600}"
INTERVAL="${3:-1}"
OUT_PREFIX="${4:-pingrun_$(date -u +%Y%m%dT%H%M%SZ)}"

CSV="${OUT_PREFIX}.csv"
RTT_TMP="${OUT_PREFIX}.rtt.tmp"
SORTED_RTT="${OUT_PREFIX}.rtt.sorted"
P99_TIMESTAMPS="${OUT_PREFIX}.p99_timestamps.txt"
SUMMARY="${OUT_PREFIX}.summary.txt"

# Clean old artifacts if any
rm -f "$CSV" "$RTT_TMP" "$SORTED_RTT" "$P99_TIMESTAMPS" "$SUMMARY"

echo "writing to: $OUT_PREFIX.{csv,summary.txt,p99_timestamps.txt}"

# Header
echo "timestamp_utc,seq,rtt_ms" >> "$CSV"

# We'll send a fixed count based on duration and interval (works on macOS & Linux)
COUNT=$(( DURATION / INTERVAL ))

# macOS 'date' differs; we'll stick to a portable UTC ISO format from 'date -u'
# Parse ping output lines, extracting seq and rtt; add our own timestamp at capture time.
# We deliberately ignore lines without a time= (timeouts) but count them later via ping's summary.
# NOTE: On Linux, 'icmp_seq='; on macOS, 'icmp_seq=' too. If missing, we'll leave seq blank.
PING_CMD=( ping -n -c "$COUNT" -i "$INTERVAL" "$HOST" )

# Run ping and capture per-reply measurements
# shellcheck disable=SC2068
"${PING_CMD[@]}" 2>/dev/null | while IFS= read -r line; do
  # Only lines with 'time=' are successful replies.
  if [[ "$line" == *"time="* ]]; then
    # UTC timestamp
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Extract seq if present (icmp_seq=NUMBER)
    seq=""
    if [[ "$line" =~ icmp_seq=([0-9]+) ]]; then
      seq="${BASH_REMATCH[1]}"
    fi

    # Extract rtt in ms (time=NUMBER ms)
    rtt=""
    if [[ "$line" =~ time=([0-9]*\.?[0-9]+)[[:space:]]*ms ]]; then
      rtt="${BASH_REMATCH[1]}"
    fi

    if [[ -n "$rtt" ]]; then
      echo "$ts,$seq,$rtt" >> "$CSV"
      echo "$rtt" >> "$RTT_TMP"
    fi
  fi
done

# Sort RTTs ascending for percentile math
if [[ -s "$RTT_TMP" ]]; then
  LC_ALL=C sort -n "$RTT_TMP" > "$SORTED_RTT"
else
  echo "No successful replies recorded (all timeouts?). Exiting." | tee "$SUMMARY"
  exit 1
fi

N=$(wc -l < "$SORTED_RTT" | tr -d '[:space:]')

# Helper to fetch a percentile using nearest-rank method
# pctl_value P => prints value at ceil(P/100 * N)
pctl_value () {
  local P=$1
  # ceil(P/100 * N)
  # Avoid floating issues by using awk
  local idx
  idx=$(awk -v P="$P" -v N="$N" 'BEGIN{ val=P/100.0*N; idx=int(val); if (val>idx) idx=idx+1; if (idx<1) idx=1; if (idx>N) idx=N; print idx }')
  sed -n "${idx}p" "$SORTED_RTT"
}

MIN=$(sed -n '1p' "$SORTED_RTT")
MAX=$(sed -n "${N}p" "$SORTED_RTT")
P50=$(pctl_value 50)
P90=$(pctl_value 90)
P99=$(pctl_value 99)

# Extract ping's own summary to get transmitted/received/loss
# We’ll run a tiny extra ping to get a clean summary quickly (1 packet) just to parse format;
# But better: re-run same ping to host with zero sends? Not possible. Instead parse from system ping output in CSV run.
# Simpler: compute loss from expected COUNT and observed N lines.
SENT="$COUNT"
RECV="$N"
LOSS_PCT=$(awk -v s="$SENT" -v r="$RECV" 'BEGIN{ if (s>0) printf("%.2f", 100.0*(s-r)/s); else print "0.00"; }')

# Gather timestamps at/above P99
awk -F',' -v p99="$P99" 'NR>1 && $3+0 >= p99 { print $1 "  rtt_ms=" $3 }' "$CSV" > "$P99_TIMESTAMPS"

# Write summary
{
  echo "Host: $HOST"
  echo "Duration (s): $DURATION"
  echo "Interval (s): $INTERVAL"
  echo "Sent: $SENT"
  echo "Received: $RECV"
  echo "Loss (%): $LOSS_PCT"
  echo
  echo "Latency (ms):"
  echo "  min : $MIN"
  echo "  p50 : $P50"
  echo "  p90 : $P90"
  echo "  p99 : $P99"
  echo "  max : $MAX"
  echo
  echo "CSV: $CSV"
  echo "P99 timestamps (>= $P99 ms): $P99_TIMESTAMPS"
} | tee "$SUMMARY"
