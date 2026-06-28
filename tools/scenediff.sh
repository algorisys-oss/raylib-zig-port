#!/usr/bin/env bash
# scenediff.sh — the C-vs-Zig differential gate.
#
# Runs both scene_runner executables (one linked against the all-C oracle raylib,
# one against the Zig-swapped raylib) under the SAME deterministic software
# rasterizer (mesa llvmpipe), then byte-diffs the dumped framebuffers. Identical
# bytes ⇒ the ported Zig modules render identically to upstream C.
#
# Usage: scenediff.sh <runner_oracle> <runner_zig>
# Exit 0 = all scenes byte-identical; nonzero = at least one mismatch.
#
# llvmpipe is byte-exact deterministic for raylib's GL3.3 codepath (verified in
# Phase 0). DISPLAY must point at a running X server (GLFW needs a window even
# when hidden). Override with RAYLIB_ZIG_DISPLAY if :0 isn't right.
set -uo pipefail

ORACLE="${1:?need oracle runner}"
ZIG="${2:?need zig runner}"

export DISPLAY="${RAYLIB_ZIG_DISPLAY:-${DISPLAY:-:0}}"
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/c" "$TMP/zig"

echo "== rendering oracle (all-C) under llvmpipe =="
"$ORACLE" "$TMP/c"   > "$TMP/c.manifest"   || { echo "oracle runner failed"; exit 3; }
echo "== rendering zig (swapped) under llvmpipe =="
"$ZIG"    "$TMP/zig" > "$TMP/zig.manifest"  || { echo "zig runner failed"; exit 3; }

fail=0
total=0
while read -r idx name dims crc; do
  total=$((total+1))
  f="${idx}_${name}.raw"
  if cmp -s "$TMP/c/$f" "$TMP/zig/$f"; then
    printf "  PASS  %s %s\n" "$name" "$dims"
  else
    fail=$((fail+1))
    printf "  FAIL  %s %s  (framebuffers differ)\n" "$name" "$dims"
  fi
done < "$TMP/c.manifest"

if ! diff -q "$TMP/c.manifest" "$TMP/zig.manifest" >/dev/null; then
  echo "  NOTE  manifests differ (crc/scene set mismatch):"
  diff "$TMP/c.manifest" "$TMP/zig.manifest" | sed 's/^/    /'
  fail=$((fail+1))
fi

echo "------------------------------------------------------------"
if [ "$fail" -eq 0 ]; then
  echo "OK  $total/$total scenes byte-identical (C == Zig under llvmpipe)"
  exit 0
else
  echo "DIFF  $fail issue(s) across $total scenes"
  exit 1
fi
