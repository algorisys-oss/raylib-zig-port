#!/usr/bin/env bash
# webdiff.sh — the browser examples gate: web examples, C vs Zig, in headless Chrome.
#
# `zig build webexamples` builds every example in build.zig's `web_examples`
# twice for wasm32-emscripten — the unmodified upstream C example on the all-C
# library (the oracle), and its Zig-API translation on the Zig library — each
# shimmed for determinism exactly as the desktop gate does (tools/exdiff).
# This script runs both in headless Chrome (tools/webdiff/run.mjs, WebGL 2 on
# SwiftShader), reads back the final frame, and byte-compares the PNGs.
#
# Usage: webdiff.sh <c-dir> <zig-dir> <list-file> [name-filter]
#   <c-dir>/<name>/ and <zig-dir>/<name>/ hold <name>.js/.wasm(/.data).
#   list-file: one example name per line.
#   name-filter: only run examples whose name contains it ('' = all).
# Env: WEBDIFF_FRAMES (default 240), WEBDIFF_KEEP=<dir> keeps both PNGs per example.
set -uo pipefail

C_DIR="${1:?need C dir}"
ZIG_DIR="${2:?need Zig dir}"
LIST="${3:?need list file}"
FILTER="${4:-}"
FRAMES="${WEBDIFF_FRAMES:-240}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$HERE/webdiff/run.mjs"
if [ ! -d "$HERE/webdiff/node_modules/playwright" ]; then
  echo "webdiff: Playwright missing; run: (cd tools/webdiff && npm install)"
  exit 3
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
failed=()
while read -r name; do
  [ -z "$name" ] && continue
  case "$name" in *"$FILTER"*) ;; *) continue ;; esac

  c_png="$TMP/$name.c.png"
  z_png="$TMP/$name.zig.png"
  if ! node "$RUN" "$C_DIR/$name" "$name" "$c_png" "$FRAMES"; then
    echo "  FAIL  $name (C oracle did not run)"
    fail=$((fail + 1)); failed+=("$name"); continue
  fi
  if ! node "$RUN" "$ZIG_DIR/$name" "$name" "$z_png" "$FRAMES"; then
    echo "  FAIL  $name (Zig did not run)"
    fail=$((fail + 1)); failed+=("$name"); continue
  fi
  if [ -n "${WEBDIFF_KEEP:-}" ]; then
    mkdir -p "$WEBDIFF_KEEP"
    cp "$c_png" "$WEBDIFF_KEEP/$name.c.png"
    cp "$z_png" "$WEBDIFF_KEEP/$name.zig.png"
  fi
  if cmp -s "$c_png" "$z_png"; then
    echo "  PASS  $name"
    pass=$((pass + 1))
  else
    echo "  FAIL  $name (final frames differ)"
    fail=$((fail + 1)); failed+=("$name")
  fi
done < "$LIST"

echo "------------------------------------------------------------"
total=$((pass + fail))
if [ "$fail" -eq 0 ]; then
  echo "OK  $pass/$total web examples byte-identical (C == Zig in headless Chrome)"
  exit 0
fi
echo "FAIL  $pass/$total passed; failing: ${failed[*]}"
exit 1
