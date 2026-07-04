#!/usr/bin/env bash
# audiodiff.sh — the C-vs-Zig differential gate for raudio (PCM/metadata diff).
#
# Runs both audiocheck executables (one linked against the all-C oracle raylib,
# one against the Zig-swapped raylib) and byte-diffs their reports: decoded PCM
# hashes (WAV/OGG/MP3/QOA), Wave op results, export round-trips, music/stream
# metadata. Identical output ⇒ the Zig raudio decodes identically to upstream C.
#
# Usage: audiodiff.sh <audiocheck_oracle> <audiocheck_zig>
# Exit 0 = reports byte-identical; nonzero = divergence (shown as a diff).
set -uo pipefail

ORACLE="${1:?need oracle audiocheck}"
ZIG="${2:?need zig audiocheck}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/c" "$TMP/zig"

echo "== decoding via oracle (all-C) =="
"$ORACLE" "$TMP/c" > "$TMP/c.report" || { echo "oracle audiocheck failed"; exit 3; }
echo "== decoding via zig (swapped) =="
"$ZIG" "$TMP/zig" > "$TMP/zig.report" || { echo "zig audiocheck failed"; exit 3; }

total=$(wc -l < "$TMP/c.report")
if diff -u "$TMP/c.report" "$TMP/zig.report" > "$TMP/report.diff"; then
  echo "------------------------------------------------------------"
  echo "OK  $total/$total audio checks byte-identical (C == Zig)"
  exit 0
else
  echo "------------------------------------------------------------"
  echo "DIFF  audio reports diverge:"
  sed 's/^/  /' "$TMP/report.diff"
  exit 1
fi
