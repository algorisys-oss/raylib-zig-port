// raygui_impl.c — instantiates vendored raygui (vendor/raygui/raygui.h) as C,
// for the `raygui` Zig binding module. raygui is linked, not ported (see
// vendor/raygui/README.md). It calls raylib through the public C ABI.
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"
