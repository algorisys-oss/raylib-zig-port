# Migration workflow — how modules get ported

The agent-driven process that moves the port forward, one translation unit at a
time. Read alongside [testing.md](testing.md) (the gates), [architecture.md](architecture.md)
(the swap mechanism), [../CLAUDE.md](../CLAUDE.md) (conventions), and
[../PROGRESS.md](../PROGRESS.md) (status / resume point).

The guiding rule: **the differential against pure-C raylib is the spec** (raylib
has no test suite — see [testing.md](testing.md)). Everything below keeps that
gate honest while porting at scale.

## The role split

Porting is parallelized with sub-agents, with a strict division of labor (this is
what kept the sqlite-zig marathon from drifting into a broken engine):

- **The orchestrator (main session)** owns shared state and the gate. It picks
  the next module bottom-up, spawns one drafting agent, then *independently*
  verifies and commits. It never writes the module's Zig itself.
- **One drafting sub-agent per module** does the read-C / write-Zig work in a
  fresh context, producing `src/<name>.zig`.

Shared files — [../build.zig](../build.zig) (`ported_modules`), the harnesses in
[../test](../test), and the offset tooling — are touched **only by the
orchestrator**. Drafting is parallel and disposable (a bad draft is just redone);
**verification is serial, owned by one actor, and gated on the differential.**

## The per-module loop

1. **Pick** the next module per [../plan.md](../plan.md) (bottom-up: raymath →
   rlgl → rshapes/rtextures/rtext → rcore+glfw → rmodels/raudio), so each Zig
   layer rests on already-ported Zig.
2. **Draft** it with a fresh sub-agent (prompt shape below).
3. **Wire it in:** add `"<name>.c"` to `ported_modules` in build.zig; add any new
   struct offsets to the offset tooling (for global/ABI-shared structs).
4. **Validate** — must be green (see [testing.md](testing.md)):
   - `zig build` (Debug) builds the swapped library.
   - `zig build test` — C-vs-Zig framebuffer diff under llvmpipe → **byte-identical**.
   - For raymath: `zig build mathtest` → **bit-exact**.
   - As example coverage grows, the relevant examples render-match.
5. **Commit** — only when green. Update [../PROGRESS.md](../PROGRESS.md) and
   [../plan.md](../plan.md); log tokens/time; tag at phase boundaries.

**Never commit anything whose differential isn't clean.** The last committed
state must always build and render identically to pure-C raylib.

## The drafting-agent prompt template

Each module gets a fresh sub-agent with a self-contained prompt:

```
Port vendor/raylib/src/<module>.c (or .h) to src/<module>.zig.
DO THE WORK YOURSELF — do not spawn further agents. Read the whole C file first.

Contract (ABI — stays C-compatible):
- export the SAME C-ABI symbols the C exports (match raylib.h / rlgl.h signatures
  and the RLAPI/RMAPI names). Every still-C caller must link unchanged.
- mirror ABI-shared structs (CoreData/rlglData/public types) as extern struct,
  field-for-field; pass Color/Vector*/Rectangle/Matrix BY VALUE (extern struct).

Idiom (the quality bar — Zig as if by Andrew Kelley, API design as Raysan's):
- clean idiomatic Zig (errors, slices, comptime for #ifdef), zig fmt-clean,
  EXCEPT at the ABI boundary which stays byte-compatible. Keep raylib's public
  API shape exactly.

Validate (the bar, not optional):
- zig build && zig build test  → framebuffers byte-identical (C == Zig, llvmpipe)
- for pure-math/leaf modules add/extend the numeric diff
```

## The gotcha checklist (carry forward — grows with every bug)

Every entry is a real failure class. Verify each before claiming a module done.
The raylib-specific ones, then the ones inherited from sqlite-zig:

- **Macro constant TYPE (float vs double).** `PI`/`DEG2RAD` etc. are often
  `...f` (float) in one config and double in another (e.g. raylib's `PI` is
  float in non-standalone mode, double only under `*_STANDALONE`). A wrong type
  changes a whole expression's promotion → 1-ULP diffs. Confirm the macro's type
  in the ACTIVE config; `atan2f(...)*(180.0f/PI)` is all-f32 when PI is float.
- **Float op-order & libm.** Preserve FP grouping from the C exactly (not
  associative); disable contraction; call the **same libm** (`sinf`/`cosf`/…) via
  `extern`, not `std.math` (last-ULP differences fail the bit-exact gate).
- **By-value struct ABI.** `Color`/`Vector*`/`Rectangle`/`Matrix` cross the ABI by
  value — keep them `extern struct`; a layout/convention mismatch corrupts args
  silently.
- **Global-state layout.** `CoreData CORE` and `rlglData RLGL` are read across
  modules — mirror with `extern struct` + comptime `@offsetOf`/`@sizeOf` asserts
  vs C ground truth; a wrong mirror must fail to *compile*, never corrupt at
  runtime.
- **Pinned config constants.** Re-probe every `GRAPHICS_API_*`/`PLATFORM_*`/
  `SUPPORT_*`-gated value against the actual config; constant drift bit every
  sqlite-zig port.
- **Return-register width.** A function returning `u8`/`i16`/`bool` declared
  `c_int` by callers leaks garbage upper bits on x86-64. Declare the exact C
  return type.
- **`@truncate` vs `@intCast`.** C's `(u8)x` truncates; Zig's `@intCast` panics on
  overflow. Port truncating casts as `@truncate`.
- **`@memmove` for overlap.** Use `@memmove` wherever source/dest can overlap
  (`@memcpy` is UB then).
- **Inline array vs pointer.** Know whether a struct field is an inline array
  (take its address) or a pointer (dereference). Getting it backwards segfaults.

The throughline (same as sqlite-zig): porting the *logic* is the easy part;
getting struct layout, by-value ABI, float op-order, and constants **exact
against C ground truth** is the hard part — and the differential gate is the only
thing that catches it.
