#!/usr/bin/env python3
"""constaudit.py — mechanical audit of hand-mirrored C constants in src/*.zig.

Every Zig module keeps private copies of raylib enum values and #defines; two
modules can each look plausible and still disagree with the header (this is how
rcore's ShaderLocationIndex drifted +1 and silently broke GPU instancing).

Parses every `typedef enum { ... }` / `enum { ... }` member (with implicit
increments) and every numeric `#define NAME <int-expr>` in raylib's own
top-level sources (vendor/raylib/src/*.h, *.c — not external/), plus string
`#define NAME "..."`, then checks
every `const NAME[: T] = <int|bool|"string">;` in src/*.zig whose NAME the C side defines.
A Zig value passes when it equals ANY C definition of that name (headers
define some names differently per #if branch). Commented-out lines
(`//#define`) are ignored.

Usage: python3 tools/constaudit.py [c_src_dir] [zig_src_dir]
Exit status 1 when any mismatch is found.
"""
import pathlib
import re
import sys

C_DIR = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "vendor/raylib/src")
ZIG_DIR = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "src")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def c_int(expr, known):
    """Evaluate a C integer constant expression, or None if it isn't one."""
    expr = re.sub(r"\b(0[xX][0-9a-fA-F]+|\d+)[uUlL]+\b", r"\1", expr.strip())
    expr = re.sub(r"\((?:unsigned\s+)?(?:int|long|short|char)\)", "", expr)
    if not re.fullmatch(r"[\w\s()+\-*/<>|&~^]+", expr):
        return None
    names = set(re.findall(r"\b[A-Za-z_]\w*\b", expr))
    if any(n not in known for n in names):
        return None
    try:
        value = eval(expr.replace("/", "//"), {"__builtins__": {}},
                     {n: known[n][0] for n in names})
    except Exception:
        return None
    return value if isinstance(value, int) else None


def parse_c(paths):
    defs = {}  # name -> [values]

    def add(name, value):
        defs.setdefault(name, [])
        if value not in defs[name]:
            defs[name].append(value)

    for path in paths:
        text = strip_comments(path.read_text(errors="replace"))
        for m in re.finditer(r"^\s*#\s*define\s+([A-Z_][A-Z0-9_]*)\s+(.+)$", text, re.M):
            string = re.fullmatch(r'\s*"((?:[^"\\]|\\.)*)"\s*', m.group(2))
            value = string.group(1) if string else c_int(m.group(2), defs)
            if value is not None:
                add(m.group(1), value)
        for body in re.findall(r"\benum\s*\w*\s*\{(.*?)\}", text, re.S):
            nxt = 0
            for item in body.split(","):
                item = item.strip()
                if not item:
                    continue
                name, _, init = item.partition("=")
                name = name.strip()
                if not re.fullmatch(r"[A-Za-z_]\w*", name):
                    continue
                if init:
                    value = c_int(init, defs)
                    if value is None:
                        break  # can't follow the implicit sequence past this
                    nxt = value
                add(name, nxt)
                nxt += 1
    return defs


ZIG_CONST = re.compile(
    r"^\s*(?:pub\s+)?const\s+([A-Z_][A-Z0-9_]*)\s*(?::[^=]+)?=\s*"
    r"(-?(?:0x[0-9a-fA-F_]+|\d[\d_]*)|true|false|\"(?:[^\"\\\\]|\\\\.)*\")\s*;", re.M)


def main():
    c_paths = sorted(p for p in C_DIR.iterdir() if p.suffix in (".h", ".c"))
    defs = parse_c(c_paths)
    checked = 0
    mismatches = []
    for zig in sorted(ZIG_DIR.rglob("*.zig")):
        for line_no, line in enumerate(zig.read_text().splitlines(), 1):
            m = ZIG_CONST.match(line)
            if not m or m.group(1) not in defs:
                continue
            checked += 1
            literal = m.group(2)
            if literal.startswith('"'):  # string #define (e.g. RAYLIB_VERSION)
                value = literal[1:-1]
            elif literal in ("true", "false"):  # config.h flags mirrored as bool
                value = int(literal == "true")
            else:
                value = int(literal.replace("_", ""), 0)
            if value not in defs[m.group(1)]:
                mismatches.append(f"{zig}:{line_no}  {m.group(1)} = {value}  "
                                  f"(C: {', '.join(map(str, defs[m.group(1)]))})")
    for line in mismatches:
        print("MISMATCH", line)
    print(f"{'FAIL' if mismatches else 'OK'}  {checked} mirrored constants checked "
          f"against {len(c_paths)} C sources; {len(mismatches)} mismatch(es)")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
