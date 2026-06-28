#!/usr/bin/env bash
# mathdiff.sh — rcamera bit-exact numeric gate.
# Runs the C oracle and the Zig harness over the identical input stream and
# diffs their raw-float-bits output. Identical ⇒ src/rcamera.zig is bit-exact
# with C rcamera. Usage: mathdiff.sh <camgrid_c> <camgrid_zig>
set -uo pipefail
C="${1:?need camgrid_c}"
Z="${2:?need camgrid_zig}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
"$C" > "$TMP/c.txt" || { echo "C oracle failed"; exit 3; }
"$Z" > "$TMP/z.txt" || { echo "Zig harness failed"; exit 3; }
if diff -q "$TMP/c.txt" "$TMP/z.txt" >/dev/null; then
  lines=$(wc -l < "$TMP/c.txt")
  vals=$(wc -w < "$TMP/c.txt")
  echo "OK  rcamera bit-exact: $lines iterations, $vals values byte-identical (C == Zig)"
  exit 0
else
  echo "DIFF  rcamera mismatch — first differing lines:"
  diff "$TMP/c.txt" "$TMP/z.txt" | head -20
  nbad=$(diff "$TMP/c.txt" "$TMP/z.txt" | grep -c '^<')
  echo "($nbad differing iteration-lines)"
  exit 1
fi
