# Review response: from "C with Zig keywords" to idiomatic Zig

On 2026-10-16 an external reviewer read the port and wrote, in short:

> directly calling into clib doesn't look very Ziggy … The code is pretty much
> a straight translation from C to Zig without taking any advantage of Zig's
> language features (optionals, error results, allocators, etc) … This is C
> code written with Zig keywords, not Zig code. … you might just learn bad
> habits from this codebase.

They were right. This document records what we found, what we changed, how
we kept behaviour identical while changing it, and what is still C on
purpose. The code-level lessons, with before/after snippets, are in
[idioms.md](idioms.md).

## What the review found

The port was correct, but correct the wrong way. Every gate compared C and
Zig output byte for byte and passed, yet the modules that handle files,
strings and memory were transliterated line by line:

| Measure (all of `src/`) | Before |
|---|---|
| libc `extern fn` declarations | 90 |
| libc calls (`strcmp`, `memcpy`, `snprintf`, `fopen`, …) and raw `RL_CALLOC`/`RL_FREE` | 978 |
| `[*c]` pointer types | 2136 |
| `std.mem.Allocator` uses | 0 |
| `defer` in the module internals | 1 |

The cause was simple. A byte-exact oracle rewards transliteration, because
it's the fastest way to match C. Nothing measured idiom, so idiom didn't
happen. Our own CLAUDE.md asked for idiomatic internals; nothing enforced it.

## What changed

### The rule

C shapes belong only at the ABI edge. raylib's public API must stay C
(`export fn`, `[*c]u8`, `extern struct`, `callconv(.c)`), so each module keeps
thin export wrappers. Behind them, the logic is ordinary Zig: slices, error
unions, `std.Io`, `Allocator`, `defer`, `std.mem`/`std.fmt`/`std.crypto`.

### Per module

| Module | What moved |
|---|---|
| rcore (+ desktop and web backends) | File system logic to `fs.zig`; automation events file to `automation.zig`; MD5/SHA-1/SHA-256/CRC32/base64 encode replaced by `std.crypto`, `std.hash`, `std.base64`; dropped files and gamepad names through shared helpers; `OpenURL` starts `xdg-open` with an argv instead of `sprintf` + `system()` |
| rtext | String functions to `rtext_strings.zig`, BMFont parsing to `rtext_bmfont.zig`; loaders return error unions with `errdefer`; ExportFontAsCode through `Io.Writer.Allocating` |
| rtextures | Five copies of the per-format pixel switch became shared codecs; half-float and image-as-code to `rtextures_encode.zig` |
| rmodels | IQM layout to `rmodels_iqm.zig` (reads structs from bytes, no memcpy); one OBJ mesh splitter instead of three face walks; bounds-checked glTF accessor reader; cubicmap faces as a data table |
| raudio | `std.DoublyLinkedList` for the two hand-rolled lists; one `AudioFormat` enum; one music decode loop instead of four; wave helpers to `raudio_wave.zig` |
| rlgl | Batch and buffer allocation with `errdefer`; quad index pattern and readback flip to `rlgl_buffers.zig` |

Shared across modules:

- `cmem.zig`: the one place that touches the C heap, for memory raylib
  returns to C callers (who release it with `free`).
- `cscan.zig`: one reproduction of the glibc `sscanf` rules raylib's text
  formats depend on, used by the automation and BMFont parsers.

Every std-only helper file has its own `test` blocks, run under
`std.testing.allocator`, so leaks and double frees fail the test.

### The numbers after

| Measure (all of `src/`) | Before | After |
|---|---|---|
| libc `extern fn` declarations | 90 | 6 |
| libc and raw-allocation calls | 978 | 9 |
| `[*c]` pointer types | 2136 | 1517 |

Most of the remaining `[*c]` are export signatures and the generated C
binding layer in `src/api/`, which are C by definition.

## What is still C, on purpose

Each remaining call has a comment at the call site saying why.

| C call | Why it stays |
|---|---|
| `vprintf`, `vsnprintf` | TraceLog and TextFormat receive a C printf format string and C variadic arguments. Only libc can format those. |
| `snprintf` for floats | raylib's exporters write `%f`-style floats. `std.fmt` rounds exact ties differently, and the files must match C byte for byte. |
| `fflush` | TraceLog's output flush, as in C. |
| `cmem.zig` (`calloc`/`realloc`/`free`) | Buffers raylib hands to C callers are documented as released with `free`, so they must live on the C heap. |
| libm (`sinf`, `tan`, …) | Bit-exact results need the same math library as C. Builtins that are bit-identical (`@abs`, `@floor`, `@sqrt`, `@round`) replaced their libm twins. |
| `time`, `clock_gettime`, `nanosleep` | The examples gate freezes time by preloading libc's clock. A `std.Io` clock that bypassed libc would make the gate nondeterministic. |
| stb, miniaudio, cgltf and the other vendored libraries | Third-party code, linked as C by design. |

## How behaviour stayed identical

The byte-exact gates that let the transliteration happen are also what made
the rewrite safe. The procedure for every change:

1. **Write the differential first.** For any path the 217 upstream examples
   don't reach, a small C program in `test/cdiff/` drives the functions and
   prints results and every TraceLog line. It's built twice, against C
   raylib and against the Zig library, and the outputs are byte-compared.
2. **See it pass on the old code**, so it is known to describe C's behaviour.
3. **Rewrite**, then run every gate again.
4. **Ratchet.** `tools/idiomaudit.py` counts libc declarations, calls and
   `[*c]` per file against a checked-in baseline. Counts may only go down.

The differential programs went from 4 to 12:

| Program | Covers |
|---|---|
| `core_fileio` | file I/O on a real file tree, directory scans with every filter, user callbacks |
| `core_automation` | the automation events file, including glibc `fgets`/`sscanf` edge cases |
| `audio_wave` | wave export, format conversion, crop, loaders on bad data |
| `image_ops` | image ops across all 13 pixel formats, export and load paths |
| `text_fonts` | Text* edge cases, TTF/BMFont/image fonts, crafted `.fnt` files, ExportFontAsCode |
| `models_data` | every model format and animation, ExportMesh, GenMesh* |
| `rlgl_paths` | user render batches, shader failures, readback, odd colors |
| `shapes_paths` | point-list drawing and polygon collision |

The rewrite of rcore was done by hand. The other five modules were done in
parallel, one agent per module in its own git worktree, all working from one
written brief. Each was merged and re-verified on its own before the next.

## What the rewrite found

Writing the differentials before touching code turned up **14 bugs in the
old transliteration**, all fixed. Most were crashes where C silently does
something and Zig, correctly, traps:

- `GetRayCollisionBox` crashed on any axis-aligned ray (infinity to int).
- `TextToInteger` panicked on overflow where C wraps.
- `ImageDither` crashed on a 0-bit channel; `FloatToHalf`/`HalfToFloat`
  shifted out of range.
- `rlColor4f` panicked on any component outside 0..1.
- `rlVertex3f` wrote to a stale buffer in multi-buffer render batches.
- Unused shader attribute locations (-1) panicked.
- R5G6B5 colors were scaled with a float factor where raylib uses an
  integer one.
- Missing log lines in the glTF and IQM loaders and in InitWindow.

It also turned up two things outside the port:

- **raylib 6.2 multi-page BMFont use-after-free.** `rtext.c` unloads atlas
  pages (line 2714) before drawing them into the merged atlas (line 2727).
  The port draws first, then unloads. Worth reporting upstream.
- **Two different libms in one gate.** Zig's compiler_rt carries weak
  `sinf`/`cosf`/… in the same archive member as everything else it
  provides. Zig code always pulls that member in; a pure-C program does so
  only depending on optimization level. In ReleaseFast the C side of a gate
  used glibc's math and the Zig side compiler_rt's. Every gate executable
  now pins compiler_rt's math (see CLAUDE.md).

## Verification

All on `main` after the last merge:

| Gate | Result |
|---|---|
| Upstream examples, C vs Zig (`tools/exdiff.sh`) | 217/217, Debug and ReleaseFast |
| Zig-API example translations (`zig build apiexamples`) | 217/217 |
| C-vs-Zig differentials (`zig build cdiff`) | 12/12, Debug and ReleaseFast |
| Pixel scenes (`zig build test`) | 12/12 |
| Audio (`zig build audiocheck`) | 43/43 |
| raymath / rcamera / rgestures grids | 93,000 / 7,500 / 3,200 values bit-exact |
| apitest, datacheck, constaudit | pass, pass, 0 mismatches |
| Browser gate (`zig build webexamples`) | 46/46 |
| Documentation site end-to-end | 46/46 example pages run |

Deliberate behaviour differences, all on invalid input where C crashes or
reads undefined memory, are listed in [compatibility.md](compatibility.md) §5.

## For the team

- Read [idioms.md](idioms.md) before writing Zig in this repository. Each
  section is a C habit, what replaced it, and why.
- Copy from the std-only helper files (`fs.zig`, `automation.zig`,
  `rtext_strings.zig`, `rmodels_iqm.zig`, …). They're the idiomatic core.
  The `export fn` wrappers in the modules are deliberately C-shaped; don't
  copy their style into internal code.
- Run `python3 tools/idiomaudit.py` before committing. If a count goes up,
  the change brought back a C idiom.

## Reply sent to the reviewer

> Thanks again for the review. You were right, and it's fixed now: every
> module, not just the bits you quoted.
>
> Numbers first: across the port, direct libc declarations went from 90 to 6
> and libc call sites from 978 to 9. What's left is C on purpose, and each one
> says why in a comment:
> - `vprintf`/`vsnprintf`, because raylib's TraceLog and TextFormat take C
>   printf strings with C varargs.
> - `snprintf` for float output, because std.fmt rounds ties differently and
>   the files have to match C byte for byte.
> - One small file, `cmem.zig`, owns the C heap, since raylib promises
>   callers they can `free` what it returns.
>
> How it's built now: each module keeps thin `export fn` wrappers for the C
> ABI, and the logic sits behind them in std-only files. Those use slices,
> error unions, `std.Io`, `Allocator` and `defer`, and have their own tests
> under `std.testing.allocator`.
>
> - The `FILE*`/`fopen` block you quoted is gone.
> - `ScanDirectoryFiles` and its copy-pasted counting twin are one walker that
>   takes a visitor.
> - The hand-rolled MD5, SHA and CRC32 code became `std.crypto` and
>   `std.hash`.
> - `OpenURL` starts `xdg-open` with an argv instead of building a shell
>   command with `sprintf`.
>
> To keep it from sliding back, a lint script counts libc calls per file, and
> the counts are only allowed to go down.
>
> Safety net: the port is gated byte for byte against C raylib, and every
> rewrite went through that gate. That's 217 upstream examples, pixel scenes,
> numeric grids, and now 12 C-vs-Zig differential programs for code paths
> the examples never reach. Writing those differentials first turned up 14
> real bugs in the old transliteration, plus a use-after-free in raylib 6.2's
> multi-page BMFont loader.
>
> If you want to look at the diff, the before/after lessons are in
> `docs/idioms.md`. Happy to take another round of criticism.
