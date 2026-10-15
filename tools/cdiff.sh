#!/usr/bin/env bash
# cdiff.sh — generic C-vs-Zig differential: run one test program built twice
# (against the all-C oracle raylib and the Zig-swapped raylib) with the same
# arguments, and byte-diff their stdout.
#
# For code paths the examples gate can't reach (input-gated branches, edge-case
# parameters) — see test/cdiff/*.c and the CLAUDE.md gotcha "The examples gate
# only sees what an example renders unattended".
#
# Usage: cdiff.sh <oracle_exe> <zig_exe> [args...]
# Exit 0 = outputs byte-identical; nonzero = divergence (diff shown).
set -uo pipefail

ORACLE="${1:?need oracle exe}"
ZIG="${2:?need zig exe}"
shift 2
NAME="$(basename "$ZIG")"; NAME="${NAME%_zig}"

# Programs that open a window render through mesa llvmpipe (the gate oracle).
export DISPLAY="${RAYLIB_ZIG_DISPLAY:-${DISPLAY:-:0}}"
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$ORACLE" "$@" > "$TMP/c.out" 2> "$TMP/c.err" || { echo "FAIL  $NAME: oracle run failed"; sed 's/^/  /' "$TMP/c.err" | tail -5; exit 3; }
"$ZIG" "$@" > "$TMP/zig.out" 2> "$TMP/zig.err" || { echo "FAIL  $NAME: zig run failed"; sed 's/^/  /' "$TMP/zig.err" | tail -5; exit 3; }

lines=$(wc -l < "$TMP/c.out")
if [ "$lines" -eq 0 ]; then
  echo "FAIL  $NAME: oracle produced no output"; exit 3
fi
if diff -u "$TMP/c.out" "$TMP/zig.out" > "$TMP/out.diff"; then
  echo "OK    $NAME: $lines lines byte-identical (C == Zig)"
else
  echo "DIFF  $NAME: outputs diverge"
  head -40 "$TMP/out.diff" | sed 's/^/  /'
  exit 1
fi
