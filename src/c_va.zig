//! C's `va_list` as a function argument, for forwarding the arguments of a Zig
//! C-variadic function (`...`) to vprintf-style C functions.
//!
//! `@cVaStart()` gives a `std.builtin.VaList`, and what C expects for a `va_list`
//! parameter depends on the target. Where VaList is a struct (x86-64 SysV), C's
//! `va_list` is a one-element array of it, which decays to a pointer: C gets the
//! address of the list. Where VaList is a pointer (wasm32, and most others), C's
//! `va_list` is that pointer and C gets the value. Passing `&ap` everywhere is
//! right on x86-64 only; on wasm32 it hands vprintf the address of the list and
//! the formatted output reads stack garbage (found by the web target).

const std = @import("std");

const VaList = std.builtin.VaList;
const by_pointer = @typeInfo(VaList) != .pointer;

/// The parameter type of a C function declared with `va_list`.
pub const Arg = if (by_pointer) *VaList else VaList;

/// `ap` as C's `va_list` argument.
pub fn arg(ap: *VaList) Arg {
    return if (by_pointer) ap else ap.*;
}

/// `ap` as an untyped pointer, for callbacks typed `va_list` as `void *`
/// (TraceLogCallback): the same bits C would pass.
pub fn ptr(ap: *VaList) *anyopaque {
    return @ptrCast(arg(ap));
}
