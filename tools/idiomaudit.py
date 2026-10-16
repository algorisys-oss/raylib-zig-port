#!/usr/bin/env python3
"""idiomaudit.py — ratchet on C idioms in the Zig sources.

Counts, per src/**/*.zig file:
  externs  libc `extern fn` declarations (stdio, string, memory, dirent, ...)
  calls    call sites of libc functions the file binds (by `extern fn`, by an
           alias such as `const memset = rcore.memset;`, or as `std.c.name(`) and of the RL_MALLOC/RL_CALLOC/
           RL_REALLOC/RL_FREE wrappers (raw C allocation by another name)
  cptrs    `[*c]` pointer types

libm (sinf, sqrtf, ...) is deliberately not counted: the bit-exact gates
require calling the same libm as C (CLAUDE.md, "Float bit-exactness").

The counts are compared with tools/idiomaudit.baseline.json. Any count above
its baseline fails; a file missing from the baseline is held to zero. Counts
may only go down: after a cleanup, run with --update to lower the baseline.

Usage:
  python3 tools/idiomaudit.py            # check against the baseline
  python3 tools/idiomaudit.py --update   # rewrite the baseline (refuses to raise it)
  python3 tools/idiomaudit.py --report   # print the table, no check
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "tools" / "idiomaudit.baseline.json"

LIBC = """
malloc calloc realloc free
memcpy memset memmove memcmp memchr
strcmp strncmp strlen strcpy strncpy strcat strncat strchr strrchr strstr strpbrk strspn strcspn strtok strdup
strtol strtoul strtof strtod atoi atof
sprintf snprintf vsprintf vsnprintf printf vprintf fprintf vfprintf sscanf
fopen fclose fseek ftell fread fwrite fgets fputs fputc fgetc feof ferror fflush rewind
rename remove access getcwd chdir mkdir rmdir readlink unlink
opendir readdir closedir stat lstat fstat
toupper tolower isdigit isspace isalpha isalnum isupper islower isprint
qsort bsearch
RL_MALLOC RL_CALLOC RL_REALLOC RL_FREE
""".split()

# Files whose job is to be the C boundary: counted and shown, never failed.
BOUNDARY = {
    "src/cmem.zig": "the C heap for memory raylib returns to C callers",
}

ALWAYS_C = {"RL_MALLOC", "RL_CALLOC", "RL_REALLOC", "RL_FREE"}

NAMES = "|".join(LIBC)
EXTERN_RE = re.compile(r"\bextern\s+fn\s+(" + NAMES + r")\s*\(")
# `const memset = rcore.memset;` binds a libc function another module declared.
ALIAS_RE = re.compile(r"\bconst\s+(" + NAMES + r")\s*=\s*[\w.]+\.\1\s*;")
CALL_RE = re.compile(r"(?<![\w.])(" + NAMES + r")\s*\(")
STD_C_CALL_RE = re.compile(r"\bstd\.c\.(" + NAMES + r")\s*\(")


def strip_comments(line):
    # Drop `//` comments, ignoring `//` inside string literals.
    in_str = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and in_str:
            i += 2
            continue
        if ch == '"':
            in_str = not in_str
        elif not in_str and line.startswith("//", i):
            return line[:i]
        i += 1
    return line


def strip_strings(line):
    return re.sub(r'"(\\.|[^"\\])*"', '""', line)


def code_lines(path):
    for raw in path.read_text().splitlines():
        line = strip_strings(strip_comments(raw))
        if not line.lstrip().startswith("\\\\"):  # skip multiline string literals
            yield line


def audit(path):
    lines = list(code_lines(path))
    # A libc name counts only where it is bound to libc: a Zig function that
    # happens to be called `remove` is not a C idiom.
    bound = set(ALWAYS_C)
    for line in lines:
        for regex in (EXTERN_RE, ALIAS_RE):
            m = regex.search(line)
            if m:
                bound.add(m.group(1))

    externs = calls = cptrs = 0
    for line in lines:
        cptrs += line.count("[*c]")
        if EXTERN_RE.search(line) or ALIAS_RE.search(line):
            externs += bool(EXTERN_RE.search(line))
            continue
        calls += sum(1 for m in CALL_RE.finditer(line) if m.group(1) in bound and not is_decl(line, m))
        calls += len(STD_C_CALL_RE.findall(line))
    return {"externs": externs, "calls": calls, "cptrs": cptrs}


def is_decl(line, m):
    return re.search(r"\bfn\s+$", line[: m.start()]) is not None


def collect():
    result = {}
    for path in sorted((ROOT / "src").rglob("*.zig")):
        result[str(path.relative_to(ROOT))] = audit(path)
    return result


def print_table(counts, baseline):
    print(f"{'file':42} {'externs':>8} {'calls':>8} {'cptrs':>8}")
    totals = {"externs": 0, "calls": 0, "cptrs": 0}
    for name, c in counts.items():
        base = baseline.get(name, {})
        cells = []
        for key in ("externs", "calls", "cptrs"):
            totals[key] += c[key]
            delta = c[key] - base.get(key, c[key])
            cells.append(f"{c[key]:>8}" if delta == 0 else f"{c[key]:>5}{delta:+3}")
        print(f"{name:42} {' '.join(cells)}")
    print(f"{'total':42} {totals['externs']:>8} {totals['calls']:>8} {totals['cptrs']:>8}")


def main():
    args = sys.argv[1:]
    counts = collect()
    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}

    if "--report" in args:
        print_table(counts, baseline)
        return 0

    regressions = []
    for name, c in counts.items():
        if name in BOUNDARY:
            continue
        base = baseline.get(name, {"externs": 0, "calls": 0, "cptrs": 0})
        for key, value in c.items():
            if value > base[key]:
                regressions.append(f"{name}: {key} {base[key]} -> {value}")

    if "--update" in args:
        if regressions and BASELINE.exists():
            print("refusing to raise the baseline:")
            for r in regressions:
                print("  " + r)
            return 1
        BASELINE.write_text(json.dumps(counts, indent=2) + "\n")
        print_table(counts, baseline)
        print(f"baseline written: {BASELINE.relative_to(ROOT)}")
        return 0

    print_table(counts, baseline)
    for name, reason in BOUNDARY.items():
        print(f"boundary: {name} ({reason})")
    if regressions:
        print("\nidiomaudit: C idioms increased (the baseline only goes down):")
        for r in regressions:
            print("  " + r)
        return 1
    print("\nidiomaudit: OK (no file above its baseline)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
