# Testing & validation

How correctness is established for the raylib C→Zig port. Read alongside
[architecture.md](architecture.md) (the swap mechanism), [../plan.md](../plan.md)
(roadmap), and [../PROGRESS.md](../PROGRESS.md) (status).

**The defining constraint:** raylib ships **no assertion/unit test suite** (its CI
only *builds* the examples). There is no "the test suite is the spec" to lean on
like sqlite-zig had. So we manufacture an oracle and gate every port on it. A
port is "done" only when the differential against pure-C raylib is clean — and we
report the actual diff result, never a confidence judgement.

There are three gates, cheapest first.

## 1. raymath bit-exact numeric diff — `zig build mathtest`

The cheapest gate, for the pure-math module. raymath is allocation-free,
GL-free, global-free pure functions, so it's validated **numerically** rather
than by rendering:

- [../test/mathgrid.c](../test/mathgrid.c) — the **C oracle**: includes raymath.h
  (strict IEEE: `-DRAYMATH_STATIC_INLINE -ffp-contract=off`), drives a
  deterministic LCG input stream through a representative battery of functions,
  and prints the **raw IEEE-754 bits** of every result.
- [../test/mathgrid.zig](../test/mathgrid.zig) — the **Zig harness**: the *exact*
  same LCG and call sequence, calling the Zig port's C-ABI exports via `extern
  fn` (so it exercises the real exported symbols), printing the same raw bits.
- [../tools/mathdiff.sh](../tools/mathdiff.sh) diffs the two. **Identical bytes ⇒
  bit-exact.**

Bit-exactness, not tolerance, is the bar here because pixel rendering downstream
is byte-compared — any float drift in raymath would surface as pixel diffs later.
Two rules make it achievable: (1) the Zig port calls the **same libm**
(`sinf`/`cosf`/`sqrtf`/…) via `extern`, not `std.math`, whose last-ULP results
can differ; (2) **FP op order is preserved** from the C and contraction is
disabled on both sides, so `a*b + c*d` stays exactly that.

## 2. C-vs-Zig framebuffer diff — `zig build test`

The primary gate for everything that renders. We build raylib **twice from the
same sources**: `raylib` (with ported Zig modules swapped in via `ported_modules`)
and `raylib_oracle` (forced all-C). A scene runner is linked against each, both
render an identical battery, and the framebuffers are byte-compared.

```bash
zig build test     # renders the scene battery through both libs, byte-diffs
```

- [../test/scene_runner.c](../test/scene_runner.c) renders a fixed battery of
  **deterministic** scenes (pinned sizes/colors, **no time/RNG**) to a hidden
  window and reads the framebuffer back via `LoadImageFromScreen`.
- [../tools/scenediff.sh](../tools/scenediff.sh) runs both runners under the same
  software rasterizer and byte-diffs each scene's raw RGBA.

### The oracle is mesa llvmpipe (not rlsw, not the GPU)

The key Phase-0 finding: rendering raylib's **real GL3.3 codepath** under mesa's
software rasterizer

```
DISPLAY=:0  LIBGL_ALWAYS_SOFTWARE=1  GALLIUM_DRIVER=llvmpipe
```

is **byte-exact deterministic** across runs (verified on scenes with gradients,
alpha blending, rotation, and text). That makes it a perfect differential oracle:
the C build and the Zig build, rendering the *same* codepath through the *same*
rasterizer, must produce *identical* bytes. This is stronger than the originally
planned approaches:

- **Not the GPU.** The real GPU is self-consistent but its rasterizer differs
  slightly from llvmpipe (sub-pixel/rounding), so GPU output is non-deterministic
  across drivers — a loose spot-check only, never the gate.
- **Not rlsw.** raylib's bundled `external/rlsw.h` is a *separate* GL1.1 software
  codepath; validating it would validate the wrong code. llvmpipe runs the
  GL3.3 path we actually ship. (rlsw is kept only as a documented fallback.)

### Why no committed golden images

The gate compares the two **live** builds against each other, not against
committed golden PNGs. llvmpipe output is machine/driver-specific, so goldens
wouldn't be portable — but the C-vs-Zig *relative* diff is exact on any single
machine, which is all the migration needs. (Determinism is re-checked by running
the oracle build against itself.)

### Determinism discipline

Every scene must be a **pure function of the code under test**. A first draft
called `DrawFPS()` (reads real frame timing) and the gate immediately flagged
that scene as differing between two identical C builds — proof the harness
catches nondeterminism. Rule enforced since: no time, no RNG, no frame counters
in scenes.

## 3. The example acceptance suite (all 218) — the final bar

raylib's de facto test cases are its **218 example programs**
([../vendor/raylib/examples](../vendor/raylib/examples), once wired). An example
"passes" when it builds, links against the Zig library, and its rendered frames
byte-match the all-C build under llvmpipe (audio examples diff on decoded PCM
instead of pixels). **100% done = all 218 pass.** Pass count is tracked in
[../PROGRESS.md](../PROGRESS.md). An example can only run once the modules it uses
are ported, so coverage grows with the port; none is skipped silently — anything
that can't pass is logged with a reason in [not-migrated.md](not-migrated.md).

### Tolerance only where llvmpipe can't represent a path

For GPU-only paths (custom GLSL shaders, certain blend modes — the ~35 shader
examples), llvmpipe may diverge from a real GPU. There the gate falls back to a
**tight pixel tolerance** rather than byte-exact, and those cases are marked
tolerance-validated. Byte-exact remains the default everywhere it holds.

## Bug patterns to suspect first

The same C→Zig hazards that bit sqlite-zig apply here (see
[migration-workflow.md](migration-workflow.md) for the full gotcha checklist).
The raylib-specific ones:

- **Float op-order / libm drift** → pixel or numeric diff fails on unrelated
  changes. Match libm and FP grouping exactly.
- **By-value struct ABI** (`Color`, `Vector*`, `Rectangle` passed by value) →
  silent argument corruption. Keep `extern struct`; verify aggregate lowering.
- **Global-state layout** (`CoreData CORE`, `rlglData RLGL`) read across modules
  → mirror with `extern struct` + comptime offset asserts vs C ground truth.
- **Return-register width** (a `u8`/`i16`/`bool` C return declared `c_int`) →
  garbage upper bits. Declare the exact C return type.
