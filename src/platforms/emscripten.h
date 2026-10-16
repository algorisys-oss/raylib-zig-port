// emscripten.h - the Emscripten APIs src/platforms/rcore_web.zig calls.
//
// build.zig runs this through translate-c against the emsdk sysroot and hands
// the result to rcore_web.zig as the `emscripten` module, so the HTML5 event
// structs (EmscriptenTouchEvent, EmscriptenGamepadEvent, ...) match the
// Emscripten that links the program exactly.
#include <emscripten/emscripten.h>
#include <emscripten/html5.h>
