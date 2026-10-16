#!/usr/bin/env python3
"""gen_raygui.py — generate the Zig binding for vendored raygui (vendor/raygui).

raygui is linked as C (src/c/raygui_impl.c), not ported; this binding follows
the rules of docs/zig-api.md ("raygui" section), reusing gen_api.py's parser:

  GuiButton(bounds, text)  ->  gui.button(bounds, text)      (Gui prefix dropped)
  const char *             ->  ?[:0]const u8                 (raygui accepts NULL text)
  int*/float*/bool* out    ->  *i32 / *f32 / *bool
  T* (struct)              ->  *T
  char *text, int textSize ->  []u8 (edit buffer; raygui keeps it NUL-terminated)
  char **text, int count   ->  []const [*:0]const u8
  state / control / iconId ->  State / Control / IconName enums
  property                 ->  any raygui property enum (or a raw i32)

Outputs: src/raygui/raygui.zig (binding) and src/raygui/c.zig (exact-C externs).
Usage: python3 tools/gen_raygui.py
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import gen_api as api  # noqa: E402  (reuses parser + naming helpers)

HEADER = pathlib.Path("vendor/raygui/raygui.h")
OUT_DIR = pathlib.Path("src/raygui")

# raylib types raygui's API uses (imported from the raylib binding).
RAYLIB_TYPES = ["Vector2", "Vector3", "Color", "Rectangle", "Font", "Texture2D", "GlyphInfo"]

PARAM_ENUMS = {"state": "State", "control": "Control", "iconId": "IconName"}
RETURN_ENUMS = {"GuiGetState": "State"}


def strip_gui(name):
    return name[3:] if name.startswith("Gui") and name[3].isupper() else name


def c_type(p, enums):
    base, stars = p.base, p.stars
    if base == "void" and stars:
        return "?*anyopaque"
    if base in api.C_SCALARS:
        z = api.C_SCALARS[base][0]
    else:
        z = base
    for i in range(stars):
        z = f"[*c]{'const ' if p.is_const and i == 0 else ''}{z}"
    return z


class Gen:
    def __init__(self, src):
        self.src = src
        decl = src[: src.index("#if defined(RAYGUI_IMPLEMENTATION)")]
        self.funcs = api.parse_functions(decl, "RAYGUIAPI ")
        # raygui.h also declares fallback raylib types (Vector2, Color, a `bool`
        # enum…) for its standalone mode; only raygui's own Gui* types are bound.
        self.enums = [e for e in api.parse_enums(decl) if e[0].startswith("Gui")]
        self.structs = [s for s in api.parse_structs(decl)[0] if s[0].startswith("Gui")]
        self.errors = []

    def wrap(self, fname, ret, params, comment):
        sig, call = [], []
        i = 0
        while i < len(params):
            p = params[i]
            nxt = params[i + 1] if i + 1 < len(params) else None
            pn = api.zig_ident(p.name)
            if p.stars == 0 and p.name in PARAM_ENUMS:
                sig.append(f"{pn}: {PARAM_ENUMS[p.name]}")
                call.append(f"@backingInt({pn})")
            elif p.stars == 0 and p.name == "property":
                sig.append(f"{pn}: anytype")
                call.append(f"propertyValue({pn})")
            elif p.base == "char" and p.stars == 1 and p.is_const:
                sig.append(f"{pn}: ?[:0]const u8")
                call.append(f"if ({pn}) |s| s.ptr else null")
            elif p.base == "char" and p.stars == 1 and nxt is not None and nxt.name == "textSize":
                sig.append(f"{pn}: []u8")
                call.append(f"{pn}.ptr")
                call.append(f"@intCast({pn}.len)")
                i += 2
                continue
            elif p.base == "char" and p.stars == 2 and nxt is not None and nxt.name == "count":
                sig.append(f"{pn}: []const [*:0]const u8")
                call.append(f"@ptrCast(@constCast({pn}.ptr))")
                call.append(f"@intCast({pn}.len)")
                i += 2
                continue
            elif p.base == "char" and p.stars == 1:
                # GuiValueBoxFloat's textValue: a caller-owned edit buffer.
                sig.append(f"{pn}: [*]u8")
                call.append(pn)
            elif (p.stars == 1 and p.base == "unsigned char" and p.is_const and nxt is not None
                  and nxt.name == "dataSize"):
                sig.append(f"{pn}: []const u8")
                call.append(f"{pn}.ptr")
                call.append(f"@intCast({pn}.len)")
                i += 2
                continue
            elif p.stars == 1 and p.base in api.C_SCALARS:
                sig.append(f"{pn}: *{api.C_SCALARS[p.base][1]}")
                call.append(f"@ptrCast({pn})")
            elif p.stars == 1:
                sig.append(f"{pn}: *{p.base}")
                call.append(pn)
            elif p.stars == 0 and p.base in api.C_SCALARS:
                sig.append(f"{pn}: {api.C_SCALARS[p.base][1]}")
                call.append(pn)
            elif p.stars == 0:
                sig.append(f"{pn}: {p.base}")
                call.append(pn)
            else:
                raise ValueError(f"param {p.ctype} {p.name}")
            i += 1

        name = api.camel(strip_gui(fname))
        args, cargs = ", ".join(sig), ", ".join(call)
        doc = f"/// {comment}\n" if comment else ""
        target = f"c.{fname}({cargs})"
        if fname in RETURN_ENUMS:
            return f"{doc}pub fn {name}({args}) {RETURN_ENUMS[fname]} {{\n    return @enumFromInt({target});\n}}"
        if ret.base == "char" and ret.stars == 1 and ret.is_const:
            return f"{doc}pub fn {name}({args}) [:0]const u8 {{\n    return std.mem.span({target});\n}}"
        if ret.base == "unsigned int" and ret.stars == 1:
            return f"{doc}pub fn {name}({args}) [*]u32 {{\n    return {target};\n}}"
        if ret.base == "char" and ret.stars == 2:
            return f"{doc}pub fn {name}({args}) ?[*][*:0]u8 {{\n    return @ptrCast({target});\n}}"
        if ret.stars == 0:
            rt = api.C_SCALARS[ret.base][1] if ret.base in api.C_SCALARS else ret.base
            stmt = f"{target};" if rt == "void" else f"return {target};"
            return f"{doc}pub fn {name}({args}) {rt} {{\n    {stmt}\n}}"
        raise ValueError(f"return {ret.ctype}")

    def emit_c(self):
        out = [HEADER_C]
        for fname, ret, params, _ in self.funcs:
            cps = [f"{api.zig_ident(p.name)}: {c_type(p, self.enums)}" for p in params]
            out.append(f"pub extern fn {fname}({', '.join(cps)}) {c_type(ret, self.enums)};")
        return "\n".join(out) + "\n"

    def emit(self):
        out = [HEADER_ZIG]
        for sname, fields in self.structs:
            out.append(f"pub const {strip_gui(sname)} = extern struct {{")
            for base, stars, fname, array in fields:
                z = api.C_SCALARS[base][0] if base in api.C_SCALARS else base
                out.append(f"    {api.zig_ident(fname)}: {'[' + array + ']' if array else ''}{z},")
            out.append("};\n")
        for ename, members in self.enums:
            prefix = api.common_prefix([m for m, _, _ in members]) if len(members) > 1 else ""
            out.append(f"pub const {strip_gui(ename)} = enum(c_int) {{")
            for m, v, comment in members:
                tag = api.zig_ident(m[len(prefix):].lower())
                out.append(f"    {tag} = {v},{(' // ' + comment) if comment else ''}")
            if ename == "GuiIconName":
                out.append("    _,")
            out.append("};\n")
        for fname, ret, params, comment in self.funcs:
            try:
                out.append(self.wrap(fname, ret, params, comment) + "\n")
            except ValueError as e:
                self.errors.append(f"{fname}: {e}")
        return "\n".join(out)


HEADER_C = '''// GENERATED by tools/gen_raygui.py from vendor/raygui/raygui.h — do not edit.
// Exact-C declarations of raygui (linked as C via src/c/raygui_impl.c).

const raygui = @import("raygui");
''' + "".join(f"const {t} = raygui.rl.{t};\n" for t in RAYLIB_TYPES) + "const GuiStyleProp = raygui.StyleProp;\n"

HEADER_ZIG = '''// GENERATED by tools/gen_raygui.py from vendor/raygui/raygui.h — do not edit.
//
//   raygui — a simple and easy-to-use immediate-mode gui library
//   Copyright (c) 2014-2026 Ramon Santamaria (@raysan5); zlib/libpng license.
//
// Zig binding for raygui (linked as C, not ported). Same functions as
// raygui.h without the `Gui` prefix (`GuiButton` -> `gui.button`); rules in
// docs/zig-api.md. Control results stay i32 as in raygui (e.g. a message
// box returns the pressed button index).

const std = @import("std");

/// The raylib binding raygui draws with.
pub const rl = @import("raylib");
/// The exact-C declarations this binding wraps.
pub const c = @import("raygui_c");

const Vector2 = rl.Vector2;
const Vector3 = rl.Vector3;
const Color = rl.Color;
const Rectangle = rl.Rectangle;
const Font = rl.Font;

/// Style property ids are per-control enums (`DefaultProperty.text_size`,
/// `SliderProperty.width`, …); any of them, or a raw integer, is accepted.
fn propertyValue(property: anytype) c_int {
    return switch (@typeInfo(@TypeOf(property))) {
        .@"enum" => @backingInt(property),
        .int, .comptime_int => property,
        else => @compileError("raygui property must be a property enum or an integer"),
    };
}
'''


def main():
    gen = Gen(HEADER.read_text())
    zig = gen.emit()
    if gen.errors:
        print("Functions the rules cannot map:")
        for e in gen.errors:
            print("  " + e)
        sys.exit(1)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "raygui.zig").write_text(zig)
    (OUT_DIR / "c.zig").write_text(gen.emit_c())
    print(f"OK  {len(gen.funcs)} functions, {len(gen.structs)} structs, {len(gen.enums)} enums -> {OUT_DIR}/")


if __name__ == "__main__":
    main()
