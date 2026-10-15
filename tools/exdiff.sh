#!/usr/bin/env bash
# exdiff.sh — the examples acceptance gate: upstream raylib examples, C vs Zig.
#
# For each example listed in test/examples.list, compiles the UNMODIFIED
# example source from the reference raylib tree with the determinism shim
# (tools/exdiff/shim.h + driver.c), links it against BOTH libraries, runs both
# headless under llvmpipe for N frames, and byte-diffs the final-frame PNGs.
# An example passes when it builds, links, runs, and pixel-matches.
#
# Each run's cwd is a temp dir with a `resources` symlink into the example's
# category dir, so relative asset loads work and any writes the example does
# land in the temp dir — the reference tree is never written to.
#
# Usage: exdiff.sh <oracle_lib.a> <zig_lib.a> [name-filter]
#   name-filter: only run examples whose path contains the substring.
#
# List format (test/examples.list): `<category>/<file.c> [frames]`,
# '#' comments allowed. Default frames: 240.
set -uo pipefail

ORACLE_LIB="${1:?need oracle lib}"
ZIG_LIB="${2:?need zig lib}"
FILTER="${3:-}"

RAYLIB_SRC="vendor/raylib/src"
EXAMPLES="${RAYLIB_EXAMPLES:-/home/rajesh/opensource/graphics/raylib-6.2/examples}"
LIST="test/examples.list"
SYS_LIBS=(-lX11 -lXrandr -lXinerama -lXcursor -lXi -lGL -lm -lpthread -ldl -lrt)

export DISPLAY="${RAYLIB_ZIG_DISPLAY:-${DISPLAY:-:0}}"
# Default: mesa llvmpipe (deterministic software GL — the gate). EXDIFF_GPU=1
# uses the real hardware driver instead: a spot check that the llvmpipe path
# isn't masking a GPU-state bug (CLAUDE.md oracle item 4). Hardware output is
# not guaranteed bit-deterministic, so a GPU diff is a lead, not a verdict.
if [ "${EXDIFF_GPU:-0}" != 1 ]; then
  export LIBGL_ALWAYS_SOFTWARE=1
  export GALLIUM_DRIVER=llvmpipe
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Driver objects (one per lib is unnecessary — driver only uses raylib.h).
zig cc -c tools/exdiff/driver.c -o "$TMP/driver.o" -I"$RAYLIB_SRC" -std=c99 \
  || { echo "driver compile failed"; exit 3; }

# Clock freezer (see fakeclock.c): preloaded into every run so library-internal
# real-time paths (orbital cameras, gestures, wall-clock faces) are static and
# identical across the two runs.
zig cc -shared -fPIC tools/exdiff/fakeclock.c -o "$TMP/libfakeclock.so" \
  || { echo "fakeclock compile failed"; exit 3; }

pass=0; fail=0; broken=0; total=0
failures=()

while read -r entry frames; do
  case "$entry" in ''|\#*) continue ;; esac
  [ -n "$FILTER" ] && case "$entry" in *"$FILTER"*) ;; *) continue ;; esac
  frames="${frames:-240}"
  total=$((total+1))
  name="$(basename "$entry" .c)"
  category="$(dirname "$entry")"
  src="$EXAMPLES/$entry"

  if [ ! -f "$src" ]; then
    broken=$((broken+1)); failures+=("$name (source missing)")
    printf "  MISS  %s\n" "$name"; continue
  fi

  # Compile the example once (lib-independent object), link twice.
  # Flags mirror upstream examples/Makefile: gnu99 (e.g. strnlen),
  # -DPLATFORM_DESKTOP (selects GLSL 330 shaders and desktop-only paths — without
  # it shader examples silently load their GLSL 100/ES variants), and
  # -I src/external (glad.h for raylib_opengl_interop).
  if ! zig cc -c "$src" -o "$TMP/$name.o" -include tools/exdiff/shim.h \
        -I"$RAYLIB_SRC" -I"$RAYLIB_SRC/external" -DPLATFORM_DESKTOP -std=gnu99 \
        2> "$TMP/$name.cc.log"; then
    broken=$((broken+1)); failures+=("$name (compile)")
    printf "  CFAIL %s\n" "$name"; continue
  fi
  ok=1
  for side in c zig; do
    lib="$ORACLE_LIB"; [ "$side" = zig ] && lib="$ZIG_LIB"
    zig cc "$TMP/$name.o" "$TMP/driver.o" "$lib" -o "$TMP/${name}_$side" \
      -L/usr/lib/x86_64-linux-gnu "${SYS_LIBS[@]}" 2> "$TMP/$name.$side.ld.log" || ok=0
  done
  if [ "$ok" = 0 ]; then
    broken=$((broken+1)); failures+=("$name (link)")
    printf "  LFAIL %s\n" "$name"; continue
  fi

  for side in c zig; do
    # Same cwd path for both sides: examples may render the path on screen.
    run="$TMP/run"; rm -rf "$run"; mkdir -p "$run"
    [ -d "$EXAMPLES/$category/resources" ] && ln -s "$EXAMPLES/$category/resources" "$run/resources"
    # EXDIFF_SHOT is a bare name: TakeScreenshot prepends the cwd-at-InitWindow
    # base path, so absolute paths would be mangled.
    ( cd "$run" && EXDIFF_FRAMES="$frames" EXDIFF_SHOT="shot.png" \
        LD_PRELOAD="$TMP/libfakeclock.so" \
        timeout 120 "$TMP/${name}_$side" > "$TMP/$name.$side.out" 2>&1 )
    echo $? > "$TMP/$name.$side.rc"
    [ -f "$run/shot.png" ] && mv "$run/shot.png" "$TMP/$name.$side.png"
  done
  rc_c="$(cat "$TMP/$name.c.rc")"; rc_z="$(cat "$TMP/$name.zig.rc")"
  if [ "$rc_c" != 0 ] || [ "$rc_z" != 0 ]; then
    broken=$((broken+1)); failures+=("$name (run c=$rc_c zig=$rc_z)")
    printf "  RFAIL %s (c=%s zig=%s)\n" "$name" "$rc_c" "$rc_z"; continue
  fi

  if [ ! -f "$TMP/$name.c.png" ] || [ ! -f "$TMP/$name.zig.png" ]; then
    broken=$((broken+1)); failures+=("$name (no screenshot)")
    printf "  SFAIL %s (no screenshot)\n" "$name"; continue
  fi
  if cmp -s "$TMP/$name.c.png" "$TMP/$name.zig.png"; then
    pass=$((pass+1)); printf "  PASS  %s (%s frames)\n" "$name" "$frames"
  else
    fail=$((fail+1)); failures+=("$name (pixels differ)")
    printf "  FAIL  %s (pixels differ)\n" "$name"
    # Keep the diffing pair for inspection.
    mkdir -p zig-out/exdiff-failures
    cp "$TMP/$name.c.png" "zig-out/exdiff-failures/$name.c.png"
    cp "$TMP/$name.zig.png" "zig-out/exdiff-failures/$name.zig.png"
  fi
done < "$LIST"

echo "------------------------------------------------------------"
echo "examples: $pass passed, $fail pixel-diff, $broken broken, of $total run"
if [ "${#failures[@]}" -gt 0 ]; then
  printf '  issue: %s\n' ${failures[@]+"${failures[@]}"}
fi
[ $((fail+broken)) -eq 0 ]
