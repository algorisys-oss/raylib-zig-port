// rcore_web.js - the JavaScript half of src/platforms/rcore_web.zig.
//
// raylib's platforms/rcore_web.c reaches the browser with inline JavaScript
// (EM_ASM, EM_JS, EM_ASYNC_JS). Zig cannot emit those, so each snippet lives
// here as an Emscripten library function and the Zig backend calls it through
// `extern fn`. The bodies are rcore_web.c's, unchanged apart from being named.
//
// Every web link of the Zig library passes this file to emcc:
//   emcc ... --js-library src/platforms/rcore_web.js
//
// Licensed under zlib/libpng, as raylib (Copyright (c) 2013-2026 Ramon
// Santamaria (@raysan5) and contributors).

addToLibrary({
    // SetCanvasIdJs: the CSS selector of the canvas the module runs in.
    rlWebCanvasId: (out, outSize) => {
        var canvasId = "#" + Module.canvas.id;
        stringToUTF8(canvasId, out, outSize);
    },

    rlWebIsFullscreen: () => (document.fullscreenElement ? 1 : 0),
    rlWebExitFullscreen: () => { document.exitFullscreen(); },
    rlWebCanvasWidth: () => Module.canvas.width,
    rlWebCanvasStyleWidth: () => parseInt(Module.canvas.style.width),
    rlWebScreenWidth: () => screen.width,
    rlWebScreenHeight: () => screen.height,
    rlWebInnerWidth: () => window.innerWidth,
    rlWebInnerHeight: () => window.innerHeight,
    rlWebScreenX: () => window.screenX,
    rlWebScreenY: () => window.screenY,
    rlWebDevicePixelRatio: () => window.devicePixelRatio,

    // ToggleFullscreen: the setTimeout handles the browser mode change delay.
    rlWebRequestFullscreen: () => {
        setTimeout(function() {
            Module.requestFullscreen(false, false);
        }, 100);
    },

    // ToggleBorderlessWindowed: 1. the setTimeouts handle the browser mode
    // change delay, 2. the style unset handles a width="value%" like the one in
    // the default shell.html.
    rlWebRequestBorderless: (canvasIdPtr) => {
        const canvasId = UTF8ToString(canvasIdPtr);
        setTimeout(function() {
            Module.requestFullscreen(false, true);
            setTimeout(function() {
                document.querySelector(canvasId).style.width = "unset";
            }, 100);
        }, 100);
    },

    rlWebSetCanvasOpacity: (opacity) => { Module.canvas.style.opacity = opacity; },
    rlWebSetCanvasCursor: (cursorPtr) => { Module.canvas.style.cursor = UTF8ToString(cursorPtr); },
    rlWebPointerLocked: () => (document.pointerLockElement ? 1 : 0),

    rlWebClipboardWriteText: (textPtr) => { navigator.clipboard.writeText(UTF8ToString(textPtr)); },

    // RequestClipboardData: async, so the program needs -sASYNCIFY (as with
    // EM_ASYNC_JS in C).
    rlWebRequestClipboardData__async: true,
    rlWebRequestClipboardData: async () => {
        if (navigator.clipboard && window.isSecureContext) {
            let items = await navigator.clipboard.read();
            for (const item of items) {
                // Check if this item contains plain text or image
                if (item.types.includes("text/plain")) {
                    const blob = await item.getType("text/plain");
                    const text = await blob.text();
                    window._lastClipboardString = text;
                } else if (item.types.find(t => t.startsWith("image/"))) {
                    const blob = await item.getType(item.types.find(t => t.startsWith("image/")));
                    const bitmap = await createImageBitmap(blob);

                    const canvas = document.createElement('canvas');
                    canvas.width = bitmap.width;
                    canvas.height = bitmap.height;
                    const ctx = canvas.getContext('2d');
                    ctx.drawImage(bitmap, 0, 0);

                    const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height).data;

                    // Store image and data for the Fetch function
                    window._lastImgWidth = canvas.width;
                    window._lastImgHeight = canvas.height;
                    window._lastImgData = imgData;
                }
            }
        } else console.warn("Clipboard read() requires HTTPS/Localhost");
    },

    // GetLastPastedText: the string RequestClipboardData stored, copied to the
    // wasm heap (malloc'd; null when empty).
    rlWebLastPastedText__deps: ['malloc'],
    rlWebLastPastedText: () => {
        var str = window._lastClipboardString || "";
        var length = lengthBytesUTF8(str) + 1;
        if (length > 1) {
            var ptr = _malloc(length);
            stringToUTF8(str, ptr, length);
            return ptr;
        }
        return 0;
    },

    // GetLastPastedImage: the RGBA pixels RequestClipboardData stored, copied to
    // the wasm heap (malloc'd; null when there is none).
    rlWebLastPastedImage__deps: ['malloc'],
    rlWebLastPastedImage: (width, height) => {
        if (window._lastImgData) {
            const data = window._lastImgData;
            if (data.length > 0) {
                const ptr = _malloc(data.length);
                HEAPU8.set(data, ptr);

                if (width) setValue(width, window._lastImgWidth, 'i32');
                if (height) setValue(height, window._lastImgHeight, 'i32');

                // Clear the JS buffer so there is no need to fetch the same image twice
                window._lastImgData = null;

                return ptr;
            }
        }
        return 0;
    },

    // SetGamepadVibration: Chrome, Edge, Opera, Safari and Android support the
    // vibrationActuator API, Firefox only hapticActuators (2024.10.21).
    rlWebGamepadVibrate: (gamepad, leftMotor, rightMotor, duration) => {
        try {
            navigator.getGamepads()[gamepad].vibrationActuator.playEffect('dual-rumble', { startDelay: 0, duration: duration, weakMagnitude: leftMotor, strongMagnitude: rightMotor });
        } catch (e) {
            try {
                navigator.getGamepads()[gamepad].hapticActuators[0].pulse(rightMotor, duration);
            } catch (e) { }
        }
    },
});
