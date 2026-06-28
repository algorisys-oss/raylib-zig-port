//! rshapes - Basic functions to draw 2d shapes and check collisions
//!
//! Zig port of raylib's `rshapes.c`. Every public raylib shape function is exported
//! with its exact C name, byte-compatible signature, and C calling convention, so the
//! rest of raylib (still C) links against it unchanged. Floating-point operation order
//! matches the C source exactly to keep pixel output bit-identical, and libm functions
//! are called via extern declarations rather than `std.math`.
//!
//! This build mirrors raylib's default `config.h`: `SUPPORT_QUADS_DRAW_MODE` is enabled
//! and `SUPPORT_SPLINE_MITERS` is disabled, so the QUADS draw paths and the non-miter
//! `DrawSplineLinear` path are taken.

const std = @import("std");

//----------------------------------------------------------------------------------
// libm functions, called directly so results are bit-identical to the C source.
//----------------------------------------------------------------------------------
extern fn sinf(f32) f32;
extern fn cosf(f32) f32;
extern fn sqrtf(f32) f32;
extern fn acosf(f32) f32;
extern fn powf(f32, f32) f32;
extern fn ceilf(f32) f32;
extern fn fabsf(f32) f32;
extern fn fmaxf(f32, f32) f32;

//----------------------------------------------------------------------------------
// rlgl functions, provided by other translation units in the build.
//----------------------------------------------------------------------------------
extern fn rlBegin(mode: c_int) void;
extern fn rlEnd() void;
extern fn rlColor4ub(r: u8, g: u8, b: u8, a: u8) void;
extern fn rlVertex2f(x: f32, y: f32) void;
extern fn rlTexCoord2f(x: f32, y: f32) void;
extern fn rlNormal3f(x: f32, y: f32, z: f32) void;
extern fn rlSetTexture(id: c_uint) void;
extern fn rlGetMatrixTransform() Matrix;

//----------------------------------------------------------------------------------
// Defines and Macros
//----------------------------------------------------------------------------------
const PI: f32 = 3.14159265358979323846;
const DEG2RAD: f32 = PI / 180.0;

// rlgl draw modes (values copied from rlgl.h: GL_LINES/GL_TRIANGLES/GL_QUADS)
const RL_LINES: c_int = 0x0001;
const RL_TRIANGLES: c_int = 0x0004;
const RL_QUADS: c_int = 0x0007;

// Define error rate to calculate how many segments are needed to draw a smooth circle
const SMOOTH_CIRCLE_ERROR_RATE: f32 = 0.5;
// Spline segment divisions
const SPLINE_SEGMENT_DIVISIONS: c_int = 24;
// Vertex buffer length for a spline segment triangle-strip (comptime, for array sizing)
const SPLINE_VERTEX_COUNT: usize = 2 * @as(usize, @intCast(SPLINE_SEGMENT_DIVISIONS)) + 2;

// FLT_EPSILON from <float.h>
const FLT_EPSILON: f32 = 1.19209290e-7;

//----------------------------------------------------------------------------------
// Types and Structures Definition
//----------------------------------------------------------------------------------
pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Vector2 = extern struct {
    x: f32,
    y: f32,
};

pub const Vector3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Rectangle = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const Texture = extern struct {
    id: c_uint,
    width: c_int,
    height: c_int,
    mipmaps: c_int,
    format: c_int,
};
pub const Texture2D = Texture;

pub const Matrix = extern struct {
    m0: f32,
    m4: f32,
    m8: f32,
    m12: f32,
    m1: f32,
    m5: f32,
    m9: f32,
    m13: f32,
    m2: f32,
    m6: f32,
    m10: f32,
    m14: f32,
    m3: f32,
    m7: f32,
    m11: f32,
    m15: f32,
};

//----------------------------------------------------------------------------------
// Global Variables Definition
//----------------------------------------------------------------------------------
// Texture used on shapes drawing (white pixel loaded by rlgl)
var texShapes: Texture2D = .{ .id = 1, .width = 1, .height = 1, .mipmaps = 1, .format = 7 };
// Texture source rectangle used on shapes drawing
var texShapesRec: Rectangle = .{ .x = 0.0, .y = 0.0, .width = 1.0, .height = 1.0 };

//----------------------------------------------------------------------------------
// Internal helpers
//----------------------------------------------------------------------------------

// C `(int)` truncation toward zero for a float that is already in-range.
inline fn intFromFloat(comptime T: type, v: f32) T {
    return @intFromFloat(v);
}

// texShapes.width / texShapes.height as floats (C promotes the int field to float in division)
inline fn texW() f32 {
    return @floatFromInt(texShapes.width);
}
inline fn texH() f32 {
    return @floatFromInt(texShapes.height);
}

//----------------------------------------------------------------------------------
// Module Functions Definition
//----------------------------------------------------------------------------------

// Set texture and rectangle to be used on shapes drawing
export fn SetShapesTexture(texture: Texture2D, rec: Rectangle) callconv(.c) void {
    // Reset texture to default pixel if required
    if ((texture.id == 0) or (rec.width == 0) or (rec.height == 0)) {
        texShapes = .{ .id = 1, .width = 1, .height = 1, .mipmaps = 1, .format = 7 };
        texShapesRec = .{ .x = 0.0, .y = 0.0, .width = 1.0, .height = 1.0 };
    } else {
        texShapes = texture;
        texShapesRec = rec;
    }
}

// Get texture that is used for shapes drawing
export fn GetShapesTexture() callconv(.c) Texture2D {
    return texShapes;
}

// Get texture source rectangle that is used for shapes drawing
export fn GetShapesTextureRectangle() callconv(.c) Rectangle {
    return texShapesRec;
}

// Draw a pixel
export fn DrawPixel(posX: c_int, posY: c_int, color: Color) callconv(.c) void {
    DrawPixelV(.{ .x = @floatFromInt(posX), .y = @floatFromInt(posY) }, color);
}

// Draw a pixel (Vector version)
export fn DrawPixelV(position: Vector2, color: Color) callconv(.c) void {
    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);

    rlNormal3f(0.0, 0.0, 1.0);
    rlColor4ub(color.r, color.g, color.b, color.a);

    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(position.x, position.y);

    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(position.x, position.y + 1);

    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(position.x + 1, position.y + 1);

    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(position.x + 1, position.y);

    rlEnd();

    rlSetTexture(0);
}

// Draw a line (using gl lines)
export fn DrawLine(startPosX: c_int, startPosY: c_int, endPosX: c_int, endPosY: c_int, color: Color) callconv(.c) void {
    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlVertex2f(@floatFromInt(startPosX), @floatFromInt(startPosY));
    rlVertex2f(@floatFromInt(endPosX), @floatFromInt(endPosY));
    rlEnd();
}

// Draw a line defining thickness
export fn DrawLineEx(startPos: Vector2, endPos: Vector2, thick: f32, color: Color) callconv(.c) void {
    const delta = Vector2{ .x = endPos.x - startPos.x, .y = endPos.y - startPos.y };
    const length = sqrtf(delta.x * delta.x + delta.y * delta.y);

    if ((length > 0) and (thick > 0)) {
        const scale = thick / (2 * length);

        const radius = Vector2{ .x = -scale * delta.y, .y = scale * delta.x };
        var strip = [4]Vector2{
            .{ .x = startPos.x - radius.x, .y = startPos.y - radius.y },
            .{ .x = startPos.x + radius.x, .y = startPos.y + radius.y },
            .{ .x = endPos.x - radius.x, .y = endPos.y - radius.y },
            .{ .x = endPos.x + radius.x, .y = endPos.y + radius.y },
        };

        DrawTriangleStrip(&strip, 4, color);
    }
}

// Draw a line (using gl lines)
export fn DrawLineV(startPos: Vector2, endPos: Vector2, color: Color) callconv(.c) void {
    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlVertex2f(startPos.x, startPos.y);
    rlVertex2f(endPos.x, endPos.y);
    rlEnd();
}

// Draw lines sequence (using gl lines)
export fn DrawLineStrip(points: [*c]const Vector2, pointCount: c_int, color: Color) callconv(.c) void {
    if (pointCount < 2) return; // Security check

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    var i: c_int = 0;
    while (i < pointCount - 1) : (i += 1) {
        const u: usize = @intCast(i);
        rlVertex2f(points[u].x, points[u].y);
        rlVertex2f(points[u + 1].x, points[u + 1].y);
    }
    rlEnd();
}

// Draw line using cubic-bezier spline, in-out interpolation, no control points
export fn DrawLineBezier(startPos: Vector2, endPos: Vector2, thick: f32, color: Color) callconv(.c) void {
    var previous = startPos;
    var current = Vector2{ .x = 0, .y = 0 };

    var points = std.mem.zeroes([SPLINE_VERTEX_COUNT]Vector2);

    var i: c_int = 1;
    while (i <= SPLINE_SEGMENT_DIVISIONS) : (i += 1) {
        // Cubic easing in-out
        // NOTE: Easing is calculated only for y position value
        current.y = easeCubicInOut(@floatFromInt(i), startPos.y, endPos.y - startPos.y, @floatFromInt(SPLINE_SEGMENT_DIVISIONS));
        current.x = previous.x + (endPos.x - startPos.x) / @as(f32, @floatFromInt(SPLINE_SEGMENT_DIVISIONS));

        const dy = current.y - previous.y;
        const dx = current.x - previous.x;
        const size = 0.5 * thick / sqrtf(dx * dx + dy * dy);

        if (i == 1) {
            points[0].x = previous.x + dy * size;
            points[0].y = previous.y - dx * size;
            points[1].x = previous.x - dy * size;
            points[1].y = previous.y + dx * size;
        }

        const idx: usize = @intCast(2 * i);
        points[idx + 1].x = current.x - dy * size;
        points[idx + 1].y = current.y + dx * size;
        points[idx].x = current.x + dy * size;
        points[idx].y = current.y - dx * size;

        previous = current;
    }

    DrawTriangleStrip(&points, 2 * SPLINE_SEGMENT_DIVISIONS + 2, color);
}

// Draw a dashed line
export fn DrawLineDashed(startPos: Vector2, endPos: Vector2, dashSize: c_int, spaceSize: c_int, color: Color) callconv(.c) void {
    // Calculate the vector and length of the line
    const dx = endPos.x - startPos.x;
    const dy = endPos.y - startPos.y;
    const lineLength = sqrtf(dx * dx + dy * dy);

    // If the line is too short for dashing or dash size is invalid, draw a solid thick line
    if ((lineLength < @as(f32, @floatFromInt(dashSize + spaceSize))) or (dashSize <= 0)) {
        DrawLineV(startPos, endPos, color);
        return;
    }

    // Calculate the normalized direction vector of the line
    const invLineLength = 1.0 / lineLength;
    const dirX = dx * invLineLength;
    const dirY = dy * invLineLength;

    var currentPos = startPos;
    var distanceTraveled: f32 = 0;

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    while (distanceTraveled < lineLength) {
        // Calculate the end of the current dash
        var dashEndDist = distanceTraveled + @as(f32, @floatFromInt(dashSize));
        if (dashEndDist > lineLength) dashEndDist = lineLength;

        const dashEndPos = Vector2{ .x = startPos.x + dashEndDist * dirX, .y = startPos.y + dashEndDist * dirY };

        // Draw the dash segment
        rlVertex2f(currentPos.x, currentPos.y);
        rlVertex2f(dashEndPos.x, dashEndPos.y);

        // Update the distance traveled and move the current position for the next dash
        distanceTraveled = dashEndDist + @as(f32, @floatFromInt(spaceSize));
        currentPos.x = startPos.x + distanceTraveled * dirX;
        currentPos.y = startPos.y + distanceTraveled * dirY;
    }
    rlEnd();
}

// Draw a triangle
// NOTE: Vertex must be provided in counter-clockwise order
export fn DrawTriangle(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) callconv(.c) void {
    DrawTriangleGradient(v1, v2, v3, color, color, color);
}

// Draw triangle with interpolated colors (vertex in counter-clockwise order!)
export fn DrawTriangleGradient(v1: Vector2, v2: Vector2, v3: Vector2, c1: Color, c2: Color, c3: Color) callconv(.c) void {
    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);
    rlNormal3f(0.0, 0.0, 1.0);

    rlColor4ub(c1.r, c1.g, c1.b, c1.a);
    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(v1.x, v1.y);

    rlColor4ub(c2.r, c2.g, c2.b, c2.a);
    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(v2.x, v2.y);

    rlColor4ub(c3.r, c3.g, c3.b, c3.a);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(v3.x, v3.y);

    rlColor4ub(c3.r, c3.g, c3.b, c3.a);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(v3.x, v3.y);
    rlEnd();

    rlSetTexture(0);
}

// Draw a triangle using lines
// NOTE: Vertex must be provided in counter-clockwise order
export fn DrawTriangleLines(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) callconv(.c) void {
    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlVertex2f(v1.x, v1.y);
    rlVertex2f(v2.x, v2.y);

    rlVertex2f(v2.x, v2.y);
    rlVertex2f(v3.x, v3.y);

    rlVertex2f(v3.x, v3.y);
    rlVertex2f(v1.x, v1.y);
    rlEnd();
}

// Draw a triangle fan defined by points
// NOTE: First vertex provided is the center, shared by all triangles
export fn DrawTriangleFan(points: [*c]const Vector2, pointCount: c_int, color: Color) callconv(.c) void {
    if (pointCount >= 3) {
        rlSetTexture(GetShapesTexture().id);
        const shapeRect = GetShapesTextureRectangle();

        rlBegin(RL_QUADS);
        rlColor4ub(color.r, color.g, color.b, color.a);

        var i: c_int = 1;
        while (i < pointCount - 1) : (i += 1) {
            const u: usize = @intCast(i);
            rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
            rlVertex2f(points[0].x, points[0].y);

            rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
            rlVertex2f(points[u].x, points[u].y);

            rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
            rlVertex2f(points[u + 1].x, points[u + 1].y);

            rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
            rlVertex2f(points[u + 1].x, points[u + 1].y);
        }
        rlEnd();
        rlSetTexture(0);
    }
}

// Draw a triangle strip defined by points
// NOTE: Every new vertex connects with previous two
export fn DrawTriangleStrip(points: [*c]const Vector2, pointCount: c_int, color: Color) callconv(.c) void {
    if (pointCount >= 3) {
        rlBegin(RL_TRIANGLES);
        rlColor4ub(color.r, color.g, color.b, color.a);

        var i: c_int = 2;
        while (i < pointCount) : (i += 1) {
            const u: usize = @intCast(i);
            if (@rem(i, 2) == 0) {
                rlVertex2f(points[u].x, points[u].y);
                rlVertex2f(points[u - 2].x, points[u - 2].y);
                rlVertex2f(points[u - 1].x, points[u - 1].y);
            } else {
                rlVertex2f(points[u].x, points[u].y);
                rlVertex2f(points[u - 1].x, points[u - 1].y);
                rlVertex2f(points[u - 2].x, points[u - 2].y);
            }
        }
        rlEnd();
    }
}

// Draw a color-filled rectangle
export fn DrawRectangle(posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) callconv(.c) void {
    DrawRectangleV(
        .{ .x = @floatFromInt(posX), .y = @floatFromInt(posY) },
        .{ .x = @floatFromInt(width), .y = @floatFromInt(height) },
        color,
    );
}

// Draw a color-filled rectangle (Vector version)
export fn DrawRectangleV(position: Vector2, size: Vector2, color: Color) callconv(.c) void {
    DrawRectanglePro(
        .{ .x = position.x, .y = position.y, .width = size.x, .height = size.y },
        .{ .x = 0.0, .y = 0.0 },
        0.0,
        color,
    );
}

// Draw a color-filled rectangle
export fn DrawRectangleRec(rec: Rectangle, color: Color) callconv(.c) void {
    DrawRectanglePro(rec, .{ .x = 0.0, .y = 0.0 }, 0.0, color);
}

// Draw a color-filled rectangle with pro parameters
export fn DrawRectanglePro(rec: Rectangle, origin: Vector2, rotation: f32, color: Color) callconv(.c) void {
    var topLeft = Vector2{ .x = 0, .y = 0 };
    var topRight = Vector2{ .x = 0, .y = 0 };
    var bottomLeft = Vector2{ .x = 0, .y = 0 };
    var bottomRight = Vector2{ .x = 0, .y = 0 };

    // Only calculate rotation if needed
    if (rotation == 0.0) {
        const x = rec.x - origin.x;
        const y = rec.y - origin.y;
        topLeft = .{ .x = x, .y = y };
        topRight = .{ .x = x + rec.width, .y = y };
        bottomLeft = .{ .x = x, .y = y + rec.height };
        bottomRight = .{ .x = x + rec.width, .y = y + rec.height };
    } else {
        const sinRotation = sinf(rotation * DEG2RAD);
        const cosRotation = cosf(rotation * DEG2RAD);
        const x = rec.x;
        const y = rec.y;
        const dx = -origin.x;
        const dy = -origin.y;

        topLeft.x = x + dx * cosRotation - dy * sinRotation;
        topLeft.y = y + dx * sinRotation + dy * cosRotation;

        topRight.x = x + (dx + rec.width) * cosRotation - dy * sinRotation;
        topRight.y = y + (dx + rec.width) * sinRotation + dy * cosRotation;

        bottomLeft.x = x + dx * cosRotation - (dy + rec.height) * sinRotation;
        bottomLeft.y = y + dx * sinRotation + (dy + rec.height) * cosRotation;

        bottomRight.x = x + (dx + rec.width) * cosRotation - (dy + rec.height) * sinRotation;
        bottomRight.y = y + (dx + rec.width) * sinRotation + (dy + rec.height) * cosRotation;
    }

    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);

    rlNormal3f(0.0, 0.0, 1.0);
    rlColor4ub(color.r, color.g, color.b, color.a);

    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(topLeft.x, topLeft.y);

    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(bottomLeft.x, bottomLeft.y);

    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(bottomRight.x, bottomRight.y);

    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(topRight.x, topRight.y);

    rlEnd();

    rlSetTexture(0);
}

// Draw a vertical-gradient-filled rectangle
export fn DrawRectangleGradientV(posX: c_int, posY: c_int, width: c_int, height: c_int, top: Color, bottom: Color) callconv(.c) void {
    DrawRectangleGradientEx(
        .{ .x = @floatFromInt(posX), .y = @floatFromInt(posY), .width = @floatFromInt(width), .height = @floatFromInt(height) },
        top,
        bottom,
        bottom,
        top,
    );
}

// Draw a horizontal-gradient-filled rectangle
export fn DrawRectangleGradientH(posX: c_int, posY: c_int, width: c_int, height: c_int, left: Color, right: Color) callconv(.c) void {
    DrawRectangleGradientEx(
        .{ .x = @floatFromInt(posX), .y = @floatFromInt(posY), .width = @floatFromInt(width), .height = @floatFromInt(height) },
        left,
        left,
        right,
        right,
    );
}

// Draw a gradient-filled rectangle with custom vertex colors, counter-clockwise color order
export fn DrawRectangleGradientEx(rec: Rectangle, col1: Color, col2: Color, col3: Color, col4: Color) callconv(.c) void {
    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);
    rlNormal3f(0.0, 0.0, 1.0);

    // NOTE: Default raylib font character 95 is a white square
    rlColor4ub(col1.r, col1.g, col1.b, col1.a);
    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(rec.x, rec.y);

    rlColor4ub(col2.r, col2.g, col2.b, col2.a);
    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(rec.x, rec.y + rec.height);

    rlColor4ub(col3.r, col3.g, col3.b, col3.a);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(rec.x + rec.width, rec.y + rec.height);

    rlColor4ub(col4.r, col4.g, col4.b, col4.a);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(rec.x + rec.width, rec.y);
    rlEnd();

    rlSetTexture(0);
}

// Draw rectangle outline
export fn DrawRectangleLines(posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) callconv(.c) void {
    const mat = rlGetMatrixTransform();
    const xOffset = 0.5 / mat.m0;
    const yOffset = 0.5 / mat.m5;

    const fposX: f32 = @floatFromInt(posX);
    const fposY: f32 = @floatFromInt(posY);
    const fwidth: f32 = @floatFromInt(width);
    const fheight: f32 = @floatFromInt(height);

    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlVertex2f(fposX + xOffset, fposY + yOffset);
    rlVertex2f(fposX + fwidth - xOffset, fposY + yOffset);

    rlVertex2f(fposX + fwidth - xOffset, fposY + yOffset);
    rlVertex2f(fposX + fwidth - xOffset, fposY + fheight - yOffset);

    rlVertex2f(fposX + fwidth - xOffset, fposY + fheight - yOffset);
    rlVertex2f(fposX + xOffset, fposY + fheight - yOffset);

    rlVertex2f(fposX + xOffset, fposY + fheight - yOffset);
    rlVertex2f(fposX + xOffset, fposY + yOffset);
    rlEnd();
}

// Draw rectangle outline with line thickness
export fn DrawRectangleLinesEx(rec: Rectangle, thick_in: f32, color: Color) callconv(.c) void {
    var thick = thick_in;
    if ((thick > rec.width) or (thick > rec.height)) {
        if (rec.width >= rec.height) {
            thick = rec.height / 2;
        } else if (rec.width <= rec.height) {
            thick = rec.width / 2;
        }
    }

    const top = Rectangle{ .x = rec.x, .y = rec.y, .width = rec.width, .height = thick };
    const bottom = Rectangle{ .x = rec.x, .y = rec.y - thick + rec.height, .width = rec.width, .height = thick };
    const left = Rectangle{ .x = rec.x, .y = rec.y + thick, .width = thick, .height = rec.height - thick * 2.0 };
    const right = Rectangle{ .x = rec.x - thick + rec.width, .y = rec.y + thick, .width = thick, .height = rec.height - thick * 2.0 };

    DrawRectangleRec(top, color);
    DrawRectangleRec(bottom, color);
    DrawRectangleRec(left, color);
    DrawRectangleRec(right, color);
}

// Draw rectangle with rounded edges
export fn DrawRectangleRounded(rec: Rectangle, roundness_in: f32, segments_in: c_int, color: Color) callconv(.c) void {
    var roundness = roundness_in;
    var segments = segments_in;

    // Not a rounded rectangle
    if (roundness <= 0.0) {
        DrawRectangleRec(rec, color);
        return;
    }

    if (roundness >= 1.0) roundness = 1.0;

    // Calculate corner radius
    const radius = if (rec.width > rec.height) (rec.height * roundness) / 2 else (rec.width * roundness) / 2;
    if (radius <= 0.0) return;

    // Calculate number of segments to use for the corners
    if (segments < 4) {
        // Calculate the maximum angle between segments based on the error rate (usually 0.5f)
        const th = acosf(2 * powf(1 - SMOOTH_CIRCLE_ERROR_RATE / radius, 2) - 1);
        segments = intFromFloat(c_int, ceilf((2 * PI / th) / 4.0));
        if (segments <= 0) segments = 4;
    }

    const stepLength = 90.0 / @as(f32, @floatFromInt(segments));

    // Coordinates of the 12 points that define the rounded rect
    const point = [12]Vector2{
        .{ .x = rec.x + radius, .y = rec.y }, .{ .x = (rec.x + rec.width) - radius, .y = rec.y }, .{ .x = rec.x + rec.width, .y = rec.y + radius }, // P0, P1, P2
        .{ .x = rec.x + rec.width, .y = (rec.y + rec.height) - radius }, .{ .x = (rec.x + rec.width) - radius, .y = rec.y + rec.height }, // P3, P4
        .{ .x = rec.x + radius, .y = rec.y + rec.height }, .{ .x = rec.x, .y = (rec.y + rec.height) - radius }, .{ .x = rec.x, .y = rec.y + radius }, // P5, P6, P7
        .{ .x = rec.x + radius, .y = rec.y + radius }, .{ .x = (rec.x + rec.width) - radius, .y = rec.y + radius }, // P8, P9
        .{ .x = (rec.x + rec.width) - radius, .y = (rec.y + rec.height) - radius }, .{ .x = rec.x + radius, .y = (rec.y + rec.height) - radius }, // P10, P11
    };

    const centers = [4]Vector2{ point[8], point[9], point[10], point[11] };
    const angles = [4]f32{ 180.0, 270.0, 0.0, 90.0 };

    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);
    // Draw all the 4 corners: [1] Upper Left Corner, [3] Upper Right Corner, [5] Lower Right Corner, [7] Lower Left Corner
    var k: usize = 0;
    while (k < 4) : (k += 1) {
        var angle = angles[k];
        const center = centers[k];

        // NOTE: Every QUAD actually represents two segments
        var i: c_int = 0;
        while (i < @divTrunc(segments, 2)) : (i += 1) {
            rlColor4ub(color.r, color.g, color.b, color.a);
            rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
            rlVertex2f(center.x, center.y);

            rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
            rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength * 2)) * radius, center.y + sinf(DEG2RAD * (angle + stepLength * 2)) * radius);

            rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
            rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * radius, center.y + sinf(DEG2RAD * (angle + stepLength)) * radius);

            rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
            rlVertex2f(center.x + cosf(DEG2RAD * angle) * radius, center.y + sinf(DEG2RAD * angle) * radius);

            angle += (stepLength * 2);
        }

        // NOTE: In case number of segments is odd, adding one last piece to the cake
        if (@rem(segments, 2) != 0) {
            rlColor4ub(color.r, color.g, color.b, color.a);
            rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
            rlVertex2f(center.x, center.y);

            rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
            rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * radius, center.y + sinf(DEG2RAD * (angle + stepLength)) * radius);

            rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
            rlVertex2f(center.x + cosf(DEG2RAD * angle) * radius, center.y + sinf(DEG2RAD * angle) * radius);

            rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
            rlVertex2f(center.x, center.y);
        }
    }

    // [2] Upper Rectangle
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(point[0].x, point[0].y);
    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[8].x, point[8].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[9].x, point[9].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(point[1].x, point[1].y);

    // [4] Right Rectangle
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(point[2].x, point[2].y);
    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[9].x, point[9].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[10].x, point[10].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(point[3].x, point[3].y);

    // [6] Bottom Rectangle
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(point[11].x, point[11].y);
    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[5].x, point[5].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[4].x, point[4].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(point[10].x, point[10].y);

    // [8] Left Rectangle
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(point[7].x, point[7].y);
    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[6].x, point[6].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[11].x, point[11].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(point[8].x, point[8].y);

    // [9] Middle Rectangle
    rlColor4ub(color.r, color.g, color.b, color.a);
    rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
    rlVertex2f(point[8].x, point[8].y);
    rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[11].x, point[11].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
    rlVertex2f(point[10].x, point[10].y);
    rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
    rlVertex2f(point[9].x, point[9].y);

    rlEnd();
    rlSetTexture(0);
}

// Draw rectangle with rounded edges outline
export fn DrawRectangleRoundedLines(rec: Rectangle, roundness: f32, segments: c_int, color: Color) callconv(.c) void {
    // NOTE: For line thickness <=1.0f using RL_LINES, otherwise using RL_QUADS/RL_TRIANGLES
    DrawRectangleRoundedLinesEx(rec, roundness, segments, 1.0, color);
}

// Draw rectangle with rounded edges outline with line thickness
export fn DrawRectangleRoundedLinesEx(rec: Rectangle, roundness_in: f32, segments_in: c_int, thick_in: f32, color: Color) callconv(.c) void {
    var roundness = roundness_in;
    var segments = segments_in;
    var thick = thick_in;

    if (thick < 0) thick = 0;

    // Not a rounded rectangle
    if (roundness <= 0.0) {
        DrawRectangleLinesEx(.{ .x = rec.x - thick, .y = rec.y - thick, .width = rec.width + 2 * thick, .height = rec.height + 2 * thick }, thick, color);
        return;
    }

    if (roundness >= 1.0) roundness = 1.0;

    // Calculate corner radius
    const radius = if (rec.width > rec.height) (rec.height * roundness) / 2 else (rec.width * roundness) / 2;
    if (radius <= 0.0) return;

    // Calculate number of segments to use for the corners
    if (segments < 4) {
        const th = acosf(2 * powf(1 - SMOOTH_CIRCLE_ERROR_RATE / radius, 2) - 1);
        segments = intFromFloat(c_int, ceilf((2 * PI / th) / 4.0));
        if (segments <= 0) segments = 4;
    }

    const stepLength = 90.0 / @as(f32, @floatFromInt(segments));
    const outerRadius = radius + thick;
    const innerRadius = radius;

    const point = [16]Vector2{
        .{ .x = rec.x + innerRadius + 0.5, .y = rec.y - thick + 0.5 },
        .{ .x = (rec.x + rec.width) - innerRadius - 0.5, .y = rec.y - thick + 0.5 },
        .{ .x = rec.x + rec.width + thick - 0.5, .y = rec.y + innerRadius + 0.5 }, // P0, P1, P2
        .{ .x = rec.x + rec.width + thick - 0.5, .y = (rec.y + rec.height) - innerRadius - 0.5 },
        .{ .x = (rec.x + rec.width) - innerRadius - 0.5, .y = rec.y + rec.height + thick - 0.5 }, // P3, P4
        .{ .x = rec.x + innerRadius + 0.5, .y = rec.y + rec.height + thick - 0.5 },
        .{ .x = rec.x - thick + 0.5, .y = (rec.y + rec.height) - innerRadius - 0.5 },
        .{ .x = rec.x - thick + 0.5, .y = rec.y + innerRadius + 0.5 }, // P5, P6, P7
        .{ .x = rec.x + innerRadius + 0.5, .y = rec.y + 0.5 },
        .{ .x = (rec.x + rec.width) - innerRadius - 0.5, .y = rec.y + 0.5 }, // P8, P9
        .{ .x = rec.x + rec.width - 0.5, .y = rec.y + innerRadius + 0.5 },
        .{ .x = rec.x + rec.width - 0.5, .y = (rec.y + rec.height) - innerRadius - 0.5 }, // P10, P11
        .{ .x = (rec.x + rec.width) - innerRadius - 0.5, .y = rec.y + rec.height - 0.5 },
        .{ .x = rec.x + innerRadius + 0.5, .y = rec.y + rec.height - 0.5 }, // P12, P13
        .{ .x = rec.x + 0.5, .y = (rec.y + rec.height) - innerRadius - 0.5 },
        .{ .x = rec.x + 0.5, .y = rec.y + innerRadius + 0.5 }, // P14, P15
    };

    const centers = [4]Vector2{
        .{ .x = rec.x + innerRadius + 0.5, .y = rec.y + innerRadius + 0.5 },
        .{ .x = (rec.x + rec.width) - innerRadius - 0.5, .y = rec.y + innerRadius + 0.5 }, // P16, P17
        .{ .x = (rec.x + rec.width) - innerRadius - 0.5, .y = (rec.y + rec.height) - innerRadius - 0.5 },
        .{ .x = rec.x + innerRadius + 0.5, .y = (rec.y + rec.height) - innerRadius - 0.5 }, // P18, P19
    };

    const angles = [4]f32{ 180.0, 270.0, 0.0, 90.0 };

    if (thick > 1) {
        rlSetTexture(GetShapesTexture().id);
        const shapeRect = GetShapesTextureRectangle();

        rlBegin(RL_QUADS);

        // Draw all the 4 corners first: Upper Left Corner, Upper Right Corner, Lower Right Corner, Lower Left Corner
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            var angle = angles[k];
            const center = centers[k];
            var i: c_int = 0;
            while (i < segments) : (i += 1) {
                rlColor4ub(color.r, color.g, color.b, color.a);

                rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
                rlVertex2f(center.x + cosf(DEG2RAD * angle) * innerRadius, center.y + sinf(DEG2RAD * angle) * innerRadius);

                rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
                rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * innerRadius, center.y + sinf(DEG2RAD * (angle + stepLength)) * innerRadius);

                rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
                rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * outerRadius, center.y + sinf(DEG2RAD * (angle + stepLength)) * outerRadius);

                rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
                rlVertex2f(center.x + cosf(DEG2RAD * angle) * outerRadius, center.y + sinf(DEG2RAD * angle) * outerRadius);

                angle += stepLength;
            }
        }

        // Upper rectangle
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(point[0].x, point[0].y);
        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(point[8].x, point[8].y);
        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(point[9].x, point[9].y);
        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(point[1].x, point[1].y);

        // Right rectangle
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(point[2].x, point[2].y);
        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(point[10].x, point[10].y);
        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(point[11].x, point[11].y);
        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(point[3].x, point[3].y);

        // Lower rectangle
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(point[13].x, point[13].y);
        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(point[5].x, point[5].y);
        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(point[4].x, point[4].y);
        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(point[12].x, point[12].y);

        // Left rectangle
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(point[15].x, point[15].y);
        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(point[7].x, point[7].y);
        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(point[6].x, point[6].y);
        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(point[14].x, point[14].y);

        rlEnd();
        rlSetTexture(0);
    } else {
        // Use LINES to draw the outline
        rlBegin(RL_LINES);
        // Draw all the 4 corners first: Upper Left Corner, Upper Right Corner, Lower Right Corner, Lower Left Corner
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            var angle = angles[k];
            const center = centers[k];

            var i: c_int = 0;
            while (i < segments) : (i += 1) {
                rlColor4ub(color.r, color.g, color.b, color.a);
                rlVertex2f(center.x + cosf(DEG2RAD * angle) * outerRadius, center.y + sinf(DEG2RAD * angle) * outerRadius);
                rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * outerRadius, center.y + sinf(DEG2RAD * (angle + stepLength)) * outerRadius);
                angle += stepLength;
            }
        }

        // And now the remaining 4 lines
        var i: usize = 0;
        while (i < 8) : (i += 2) {
            rlColor4ub(color.r, color.g, color.b, color.a);
            rlVertex2f(point[i].x, point[i].y);
            rlVertex2f(point[i + 1].x, point[i + 1].y);
        }
        rlEnd();
    }
}

// Draw a polygon of n sides
export fn DrawPoly(center: Vector2, sides_in: c_int, radius: f32, rotation: f32, color: Color) callconv(.c) void {
    var sides = sides_in;
    if (sides < 3) sides = 3;
    var centralAngle = rotation * DEG2RAD;
    const angleStep = 360.0 / @as(f32, @floatFromInt(sides)) * DEG2RAD;

    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);
    var i: c_int = 0;
    while (i < sides) : (i += 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);
        const nextAngle = centralAngle + angleStep;

        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(center.x, center.y);

        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(centralAngle) * radius, center.y + sinf(centralAngle) * radius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(center.x + cosf(nextAngle) * radius, center.y + sinf(nextAngle) * radius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(centralAngle) * radius, center.y + sinf(centralAngle) * radius);

        centralAngle = nextAngle;
    }
    rlEnd();
    rlSetTexture(0);
}

// Draw a polygon outline of n sides
export fn DrawPolyLines(center: Vector2, sides_in: c_int, radius: f32, rotation: f32, color: Color) callconv(.c) void {
    var sides = sides_in;
    if (sides < 3) sides = 3;
    var centralAngle = rotation * DEG2RAD;
    const angleStep = 360.0 / @as(f32, @floatFromInt(sides)) * DEG2RAD;

    rlBegin(RL_LINES);
    var i: c_int = 0;
    while (i < sides) : (i += 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);

        rlVertex2f(center.x + cosf(centralAngle) * radius, center.y + sinf(centralAngle) * radius);
        rlVertex2f(center.x + cosf(centralAngle + angleStep) * radius, center.y + sinf(centralAngle + angleStep) * radius);

        centralAngle += angleStep;
    }
    rlEnd();
}

// Draw a polygon outline of n sides with line thickness
export fn DrawPolyLinesEx(center: Vector2, sides_in: c_int, radius: f32, rotation: f32, thick: f32, color: Color) callconv(.c) void {
    var sides = sides_in;
    if (sides < 3) sides = 3;
    var centralAngle = rotation * DEG2RAD;
    const exteriorAngle = 360.0 / @as(f32, @floatFromInt(sides)) * DEG2RAD;
    const innerRadius = radius - (thick * cosf(DEG2RAD * exteriorAngle / 2.0));

    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);
    var i: c_int = 0;
    while (i < sides) : (i += 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);
        const nextAngle = centralAngle + exteriorAngle;

        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(centralAngle) * radius, center.y + sinf(centralAngle) * radius);

        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(center.x + cosf(centralAngle) * innerRadius, center.y + sinf(centralAngle) * innerRadius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(nextAngle) * innerRadius, center.y + sinf(nextAngle) * innerRadius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(center.x + cosf(nextAngle) * radius, center.y + sinf(nextAngle) * radius);

        centralAngle = nextAngle;
    }
    rlEnd();
    rlSetTexture(0);
}

// Draw a color-filled circle
export fn DrawCircle(centerX: c_int, centerY: c_int, radius: f32, color: Color) callconv(.c) void {
    DrawCircleV(.{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, radius, color);
}

// Draw a color-filled circle (Vector version)
export fn DrawCircleV(center: Vector2, radius: f32, color: Color) callconv(.c) void {
    DrawCircleSector(center, radius, 0, 360, 36, color);
}

// Draw a gradient-filled circle
export fn DrawCircleGradient(center: Vector2, radius: f32, inner: Color, outer: Color) callconv(.c) void {
    rlBegin(RL_TRIANGLES);
    var i: c_int = 0;
    while (i < 360) : (i += 10) {
        const fi: f32 = @floatFromInt(i);
        rlColor4ub(inner.r, inner.g, inner.b, inner.a);
        rlVertex2f(center.x, center.y);
        rlColor4ub(outer.r, outer.g, outer.b, outer.a);
        rlVertex2f(center.x + cosf(DEG2RAD * (fi + 10)) * radius, center.y + sinf(DEG2RAD * (fi + 10)) * radius);
        rlColor4ub(outer.r, outer.g, outer.b, outer.a);
        rlVertex2f(center.x + cosf(DEG2RAD * fi) * radius, center.y + sinf(DEG2RAD * fi) * radius);
    }
    rlEnd();
}

// Draw a piece of a circle
export fn DrawCircleSector(center: Vector2, radius_in: f32, startAngle_in: f32, endAngle_in: f32, segments_in: c_int, color: Color) callconv(.c) void {
    var radius = radius_in;
    var startAngle = startAngle_in;
    var endAngle = endAngle_in;
    var segments = segments_in;

    if (startAngle == endAngle) return;
    if (radius <= 0.0) radius = 0.1; // Avoid div by zero

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) {
        const tmp = startAngle;
        startAngle = endAngle;
        endAngle = tmp;
    }

    const minSegments = intFromFloat(c_int, ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) {
        const th = acosf(2 * powf(1 - SMOOTH_CIRCLE_ERROR_RATE / radius, 2) - 1);
        segments = intFromFloat(c_int, ceilf((endAngle - startAngle) * (2 * PI / th) / 360.0));
        if (segments <= 0) segments = minSegments;
    }

    const stepLength = (endAngle - startAngle) / @as(f32, @floatFromInt(segments));
    var angle = startAngle;

    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);

    // NOTE: Every QUAD actually represents two segments
    var i: c_int = 0;
    while (i < @divTrunc(segments, 2)) : (i += 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);

        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(center.x, center.y);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength * 2.0)) * radius, center.y + sinf(DEG2RAD * (angle + stepLength * 2.0)) * radius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * radius, center.y + sinf(DEG2RAD * (angle + stepLength)) * radius);

        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * radius, center.y + sinf(DEG2RAD * angle) * radius);

        angle += (stepLength * 2.0);
    }

    // NOTE: In case number of segments is odd, adding one last piece to the cake
    if ((@as(c_uint, @bitCast(segments)) % 2) == 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);

        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(center.x, center.y);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * radius, center.y + sinf(DEG2RAD * (angle + stepLength)) * radius);

        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * radius, center.y + sinf(DEG2RAD * angle) * radius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(center.x, center.y);
    }

    rlEnd();

    rlSetTexture(0);
}

// Draw a piece of a circle outlines
export fn DrawCircleSectorLines(center: Vector2, radius_in: f32, startAngle_in: f32, endAngle_in: f32, segments_in: c_int, color: Color) callconv(.c) void {
    var radius = radius_in;
    var startAngle = startAngle_in;
    var endAngle = endAngle_in;
    var segments = segments_in;

    if (startAngle == endAngle) return;
    if (radius <= 0.0) radius = 0.1; // Avoid div by zero issue

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) {
        const tmp = startAngle;
        startAngle = endAngle;
        endAngle = tmp;
    }

    const minSegments = intFromFloat(c_int, ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) {
        const th = acosf(2 * powf(1 - SMOOTH_CIRCLE_ERROR_RATE / radius, 2) - 1);
        segments = intFromFloat(c_int, ceilf((endAngle - startAngle) * (2 * PI / th) / 360.0));
        if (segments <= 0) segments = minSegments;
    }

    const stepLength = (endAngle - startAngle) / @as(f32, @floatFromInt(segments));
    var angle = startAngle;
    const showCapLines = true;

    rlBegin(RL_LINES);
    if (showCapLines) {
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlVertex2f(center.x, center.y);
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * radius, center.y + sinf(DEG2RAD * angle) * radius);
    }

    var i: c_int = 0;
    while (i < segments) : (i += 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);

        rlVertex2f(center.x + cosf(DEG2RAD * angle) * radius, center.y + sinf(DEG2RAD * angle) * radius);
        rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * radius, center.y + sinf(DEG2RAD * (angle + stepLength)) * radius);

        angle += stepLength;
    }

    if (showCapLines) {
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlVertex2f(center.x, center.y);
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * radius, center.y + sinf(DEG2RAD * angle) * radius);
    }
    rlEnd();
}

// Draw circle outline
export fn DrawCircleLines(centerX: c_int, centerY: c_int, radius: f32, color: Color) callconv(.c) void {
    DrawCircleLinesV(.{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, radius, color);
}

// Draw circle outline (Vector version)
export fn DrawCircleLinesV(center: Vector2, radius: f32, color: Color) callconv(.c) void {
    rlBegin(RL_LINES);
    rlColor4ub(color.r, color.g, color.b, color.a);

    // NOTE: Circle outline is drawn pixel by pixel every degree (0 to 360)
    var i: c_int = 0;
    while (i < 360) : (i += 10) {
        const fi: f32 = @floatFromInt(i);
        rlVertex2f(center.x + cosf(DEG2RAD * fi) * radius, center.y + sinf(DEG2RAD * fi) * radius);
        rlVertex2f(center.x + cosf(DEG2RAD * (fi + 10)) * radius, center.y + sinf(DEG2RAD * (fi + 10)) * radius);
    }
    rlEnd();
}

// Draw circle outline with line thickness
export fn DrawCircleLinesEx(center: Vector2, radius: f32, thick: f32, color: Color) callconv(.c) void {
    DrawRing(center, radius - thick, radius, 0.0, 360.0, 36, color);
}

// Draw ellipse
export fn DrawEllipse(centerX: c_int, centerY: c_int, radiusH: f32, radiusV: f32, color: Color) callconv(.c) void {
    DrawEllipseV(.{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, radiusH, radiusV, color);
}

// Draw ellipse (Vector version)
export fn DrawEllipseV(center: Vector2, radiusH: f32, radiusV: f32, color: Color) callconv(.c) void {
    rlBegin(RL_TRIANGLES);
    var i: c_int = 0;
    while (i < 360) : (i += 10) {
        const fi: f32 = @floatFromInt(i);
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlVertex2f(center.x, center.y);
        rlVertex2f(center.x + cosf(DEG2RAD * (fi + 10)) * radiusH, center.y + sinf(DEG2RAD * (fi + 10)) * radiusV);
        rlVertex2f(center.x + cosf(DEG2RAD * fi) * radiusH, center.y + sinf(DEG2RAD * fi) * radiusV);
    }
    rlEnd();
}

// Draw ellipse outline
export fn DrawEllipseLines(centerX: c_int, centerY: c_int, radiusH: f32, radiusV: f32, color: Color) callconv(.c) void {
    DrawEllipseLinesV(.{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, radiusH, radiusV, color);
}

// Draw ellipse outline
export fn DrawEllipseLinesV(center: Vector2, radiusH: f32, radiusV: f32, color: Color) callconv(.c) void {
    rlBegin(RL_LINES);
    var i: c_int = 0;
    while (i < 360) : (i += 10) {
        const fi: f32 = @floatFromInt(i);
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlVertex2f(center.x + cosf(DEG2RAD * (fi + 10)) * radiusH, center.y + sinf(DEG2RAD * (fi + 10)) * radiusV);
        rlVertex2f(center.x + cosf(DEG2RAD * fi) * radiusH, center.y + sinf(DEG2RAD * fi) * radiusV);
    }
    rlEnd();
}

// Draw ring
export fn DrawRing(center: Vector2, innerRadius_in: f32, outerRadius_in: f32, startAngle_in: f32, endAngle_in: f32, segments_in: c_int, color: Color) callconv(.c) void {
    var innerRadius = innerRadius_in;
    var outerRadius = outerRadius_in;
    var startAngle = startAngle_in;
    var endAngle = endAngle_in;
    var segments = segments_in;

    if (startAngle == endAngle) return;

    // Function expects (outerRadius > innerRadius)
    if (outerRadius < innerRadius) {
        const tmp = outerRadius;
        outerRadius = innerRadius;
        innerRadius = tmp;

        if (outerRadius <= 0.0) outerRadius = 0.1;
    }

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) {
        const tmp = startAngle;
        startAngle = endAngle;
        endAngle = tmp;
    }

    const minSegments = intFromFloat(c_int, ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) {
        const th = acosf(2 * powf(1 - SMOOTH_CIRCLE_ERROR_RATE / outerRadius, 2) - 1);
        segments = intFromFloat(c_int, ceilf((endAngle - startAngle) * (2 * PI / th) / 360.0));
        if (segments <= 0) segments = minSegments;
    }

    // Not a ring
    if (innerRadius <= 0.0) {
        DrawCircleSector(center, outerRadius, startAngle, endAngle, segments, color);
        return;
    }

    const stepLength = (endAngle - startAngle) / @as(f32, @floatFromInt(segments));
    var angle = startAngle;

    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);
    var i: c_int = 0;
    while (i < segments) : (i += 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);

        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * outerRadius, center.y + sinf(DEG2RAD * angle) * outerRadius);

        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * innerRadius, center.y + sinf(DEG2RAD * angle) * innerRadius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * innerRadius, center.y + sinf(DEG2RAD * (angle + stepLength)) * innerRadius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * outerRadius, center.y + sinf(DEG2RAD * (angle + stepLength)) * outerRadius);

        angle += stepLength;
    }
    rlEnd();

    rlSetTexture(0);
}

// Draw ring outline
export fn DrawRingLines(center: Vector2, innerRadius_in: f32, outerRadius_in: f32, startAngle_in: f32, endAngle_in: f32, segments_in: c_int, color: Color) callconv(.c) void {
    var innerRadius = innerRadius_in;
    var outerRadius = outerRadius_in;
    var startAngle = startAngle_in;
    var endAngle = endAngle_in;
    var segments = segments_in;

    if (startAngle == endAngle) return;

    // Function expects (outerRadius > innerRadius)
    if (outerRadius < innerRadius) {
        const tmp = outerRadius;
        outerRadius = innerRadius;
        innerRadius = tmp;

        if (outerRadius <= 0.0) outerRadius = 0.1;
    }

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) {
        const tmp = startAngle;
        startAngle = endAngle;
        endAngle = tmp;
    }

    const minSegments = intFromFloat(c_int, ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) {
        const th = acosf(2 * powf(1 - SMOOTH_CIRCLE_ERROR_RATE / outerRadius, 2) - 1);
        segments = intFromFloat(c_int, ceilf((endAngle - startAngle) * (2 * PI / th) / 360.0));
        if (segments <= 0) segments = minSegments;
    }

    if (innerRadius <= 0.0) {
        DrawCircleSectorLines(center, outerRadius, startAngle, endAngle, segments, color);
        return;
    }

    const stepLength = (endAngle - startAngle) / @as(f32, @floatFromInt(segments));
    var angle = startAngle;
    const showCapLines = true;

    rlBegin(RL_LINES);
    if (showCapLines) {
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * outerRadius, center.y + sinf(DEG2RAD * angle) * outerRadius);
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * innerRadius, center.y + sinf(DEG2RAD * angle) * innerRadius);
    }

    var i: c_int = 0;
    while (i < segments) : (i += 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);

        rlVertex2f(center.x + cosf(DEG2RAD * angle) * outerRadius, center.y + sinf(DEG2RAD * angle) * outerRadius);
        rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * outerRadius, center.y + sinf(DEG2RAD * (angle + stepLength)) * outerRadius);

        rlVertex2f(center.x + cosf(DEG2RAD * angle) * innerRadius, center.y + sinf(DEG2RAD * angle) * innerRadius);
        rlVertex2f(center.x + cosf(DEG2RAD * (angle + stepLength)) * innerRadius, center.y + sinf(DEG2RAD * (angle + stepLength)) * innerRadius);

        angle += stepLength;
    }

    if (showCapLines) {
        rlColor4ub(color.r, color.g, color.b, color.a);
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * outerRadius, center.y + sinf(DEG2RAD * angle) * outerRadius);
        rlVertex2f(center.x + cosf(DEG2RAD * angle) * innerRadius, center.y + sinf(DEG2RAD * angle) * innerRadius);
    }
    rlEnd();
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Splines functions
//----------------------------------------------------------------------------------

// Draw spline: linear, minimum 2 points
// NOTE: SUPPORT_SPLINE_MITERS is disabled in this build, so the simple per-segment quad path is used.
export fn DrawSplineLinear(points: [*c]const Vector2, pointCount: c_int, thick: f32, color: Color) callconv(.c) void {
    if (pointCount < 2) return;

    var delta = Vector2{ .x = 0, .y = 0 };
    var length: f32 = 0.0;
    var scale: f32 = 0.0;

    var i: c_int = 0;
    while (i < pointCount - 1) : (i += 1) {
        const u: usize = @intCast(i);
        delta = .{ .x = points[u + 1].x - points[u].x, .y = points[u + 1].y - points[u].y };
        length = sqrtf(delta.x * delta.x + delta.y * delta.y);

        if (length > 0) scale = thick / (2 * length);

        const radius = Vector2{ .x = -scale * delta.y, .y = scale * delta.x };
        var strip = [4]Vector2{
            .{ .x = points[u].x - radius.x, .y = points[u].y - radius.y },
            .{ .x = points[u].x + radius.x, .y = points[u].y + radius.y },
            .{ .x = points[u + 1].x - radius.x, .y = points[u + 1].y - radius.y },
            .{ .x = points[u + 1].x + radius.x, .y = points[u + 1].y + radius.y },
        };

        DrawTriangleStrip(&strip, 4, color);
    }
}

// Draw spline: B-Spline, minimum 4 points
export fn DrawSplineBasis(points: [*c]const Vector2, pointCount: c_int, thick: f32, color: Color) callconv(.c) void {
    if (pointCount < 4) return;

    var a = [4]f32{ 0, 0, 0, 0 };
    var b = [4]f32{ 0, 0, 0, 0 };
    var dy: f32 = 0.0;
    var dx: f32 = 0.0;
    var size: f32 = 0.0;

    var currentPoint = Vector2{ .x = 0, .y = 0 };
    var nextPoint = Vector2{ .x = 0, .y = 0 };
    var vertices = std.mem.zeroes([SPLINE_VERTEX_COUNT]Vector2);

    var i: c_int = 0;
    while (i < (pointCount - 3)) : (i += 1) {
        var t: f32 = 0.0;
        const u: usize = @intCast(i);
        const p1 = points[u];
        const p2 = points[u + 1];
        const p3 = points[u + 2];
        const p4 = points[u + 3];

        a[0] = (-p1.x + 3.0 * p2.x - 3.0 * p3.x + p4.x) / 6.0;
        a[1] = (3.0 * p1.x - 6.0 * p2.x + 3.0 * p3.x) / 6.0;
        a[2] = (-3.0 * p1.x + 3.0 * p3.x) / 6.0;
        a[3] = (p1.x + 4.0 * p2.x + p3.x) / 6.0;

        b[0] = (-p1.y + 3.0 * p2.y - 3.0 * p3.y + p4.y) / 6.0;
        b[1] = (3.0 * p1.y - 6.0 * p2.y + 3.0 * p3.y) / 6.0;
        b[2] = (-3.0 * p1.y + 3.0 * p3.y) / 6.0;
        b[3] = (p1.y + 4.0 * p2.y + p3.y) / 6.0;

        currentPoint.x = a[3];
        currentPoint.y = b[3];

        if (i == 0) DrawCircleV(currentPoint, thick / 2.0, color); // Draw init line circle-cap

        if (i > 0) {
            vertices[0].x = currentPoint.x + dy * size;
            vertices[0].y = currentPoint.y - dx * size;
            vertices[1].x = currentPoint.x - dy * size;
            vertices[1].y = currentPoint.y + dx * size;
        }

        var j: c_int = 1;
        while (j <= SPLINE_SEGMENT_DIVISIONS) : (j += 1) {
            t = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(SPLINE_SEGMENT_DIVISIONS));

            nextPoint.x = a[3] + t * (a[2] + t * (a[1] + t * a[0]));
            nextPoint.y = b[3] + t * (b[2] + t * (b[1] + t * b[0]));

            dy = nextPoint.y - currentPoint.y;
            dx = nextPoint.x - currentPoint.x;
            size = 0.5 * thick / sqrtf(dx * dx + dy * dy);

            if ((i == 0) and (j == 1)) {
                vertices[0].x = currentPoint.x + dy * size;
                vertices[0].y = currentPoint.y - dx * size;
                vertices[1].x = currentPoint.x - dy * size;
                vertices[1].y = currentPoint.y + dx * size;
            }

            const idx: usize = @intCast(2 * j);
            vertices[idx + 1].x = nextPoint.x - dy * size;
            vertices[idx + 1].y = nextPoint.y + dx * size;
            vertices[idx].x = nextPoint.x + dy * size;
            vertices[idx].y = nextPoint.y - dx * size;

            currentPoint = nextPoint;
        }

        DrawTriangleStrip(&vertices, 2 * SPLINE_SEGMENT_DIVISIONS + 2, color);
    }

    // Cap circle drawing at the end of every segment
    DrawCircleV(currentPoint, thick / 2.0, color);
}

// Draw spline: Catmull-Rom, minimum 4 points
export fn DrawSplineCatmullRom(points: [*c]const Vector2, pointCount: c_int, thick: f32, color: Color) callconv(.c) void {
    if (pointCount < 4) return;

    var dy: f32 = 0.0;
    var dx: f32 = 0.0;
    var size: f32 = 0.0;

    var currentPoint = points[1];
    var nextPoint = Vector2{ .x = 0, .y = 0 };
    var vertices = std.mem.zeroes([SPLINE_VERTEX_COUNT]Vector2);

    DrawCircleV(currentPoint, thick / 2.0, color); // Draw init line circle-cap

    var i: c_int = 0;
    while (i < (pointCount - 3)) : (i += 1) {
        var t: f32 = 0.0;
        const u: usize = @intCast(i);
        const p1 = points[u];
        const p2 = points[u + 1];
        const p3 = points[u + 2];
        const p4 = points[u + 3];

        if (i > 0) {
            vertices[0].x = currentPoint.x + dy * size;
            vertices[0].y = currentPoint.y - dx * size;
            vertices[1].x = currentPoint.x - dy * size;
            vertices[1].y = currentPoint.y + dx * size;
        }

        var j: c_int = 1;
        while (j <= SPLINE_SEGMENT_DIVISIONS) : (j += 1) {
            t = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(SPLINE_SEGMENT_DIVISIONS));

            const q0 = (-1.0 * t * t * t) + (2.0 * t * t) + (-1.0 * t);
            const q1 = (3.0 * t * t * t) + (-5.0 * t * t) + 2.0;
            const q2 = (-3.0 * t * t * t) + (4.0 * t * t) + t;
            const q3 = t * t * t - t * t;

            nextPoint.x = 0.5 * ((p1.x * q0) + (p2.x * q1) + (p3.x * q2) + (p4.x * q3));
            nextPoint.y = 0.5 * ((p1.y * q0) + (p2.y * q1) + (p3.y * q2) + (p4.y * q3));

            dy = nextPoint.y - currentPoint.y;
            dx = nextPoint.x - currentPoint.x;
            size = (0.5 * thick) / sqrtf(dx * dx + dy * dy);

            if ((i == 0) and (j == 1)) {
                vertices[0].x = currentPoint.x + dy * size;
                vertices[0].y = currentPoint.y - dx * size;
                vertices[1].x = currentPoint.x - dy * size;
                vertices[1].y = currentPoint.y + dx * size;
            }

            const idx: usize = @intCast(2 * j);
            vertices[idx + 1].x = nextPoint.x - dy * size;
            vertices[idx + 1].y = nextPoint.y + dx * size;
            vertices[idx].x = nextPoint.x + dy * size;
            vertices[idx].y = nextPoint.y - dx * size;

            currentPoint = nextPoint;
        }

        DrawTriangleStrip(&vertices, 2 * SPLINE_SEGMENT_DIVISIONS + 2, color);
    }

    // Cap circle drawing at the end of every segment
    DrawCircleV(currentPoint, thick / 2.0, color);
}

// Draw spline: Quadratic Bezier, minimum 3 points (1 control point): [p1, c2, p3, c4...]
export fn DrawSplineBezierQuadratic(points: [*c]const Vector2, pointCount: c_int, thick: f32, color: Color) callconv(.c) void {
    if (pointCount >= 3) {
        var i: c_int = 0;
        while (i < pointCount - 2) : (i += 2) {
            const u: usize = @intCast(i);
            DrawSplineSegmentBezierQuadratic(points[u], points[u + 1], points[u + 2], thick, color);
        }
    }
}

// Draw spline: Cubic Bezier, minimum 4 points (2 control points): [p1, c2, c3, p4, c5, c6...]
export fn DrawSplineBezierCubic(points: [*c]const Vector2, pointCount: c_int, thick: f32, color: Color) callconv(.c) void {
    if (pointCount >= 4) {
        var i: c_int = 0;
        while (i < pointCount - 3) : (i += 3) {
            const u: usize = @intCast(i);
            DrawSplineSegmentBezierCubic(points[u], points[u + 1], points[u + 2], points[u + 3], thick, color);
        }
    }
}

// Draw spline segment: Linear, 2 points
export fn DrawSplineSegmentLinear(p1: Vector2, p2: Vector2, thick: f32, color: Color) callconv(.c) void {
    // NOTE: For the linear spline no subdivisions are used, only a single quad
    const delta = Vector2{ .x = p2.x - p1.x, .y = p2.y - p1.y };
    const length = sqrtf(delta.x * delta.x + delta.y * delta.y);

    if ((length > 0) and (thick > 0)) {
        const scale = thick / (2 * length);

        const radius = Vector2{ .x = -scale * delta.y, .y = scale * delta.x };
        var strip = [4]Vector2{
            .{ .x = p1.x - radius.x, .y = p1.y - radius.y },
            .{ .x = p1.x + radius.x, .y = p1.y + radius.y },
            .{ .x = p2.x - radius.x, .y = p2.y - radius.y },
            .{ .x = p2.x + radius.x, .y = p2.y + radius.y },
        };

        DrawTriangleStrip(&strip, 4, color);
    }
}

// Draw spline segment: B-Spline, 4 points
export fn DrawSplineSegmentBasis(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, thick: f32, color: Color) callconv(.c) void {
    const step = 1.0 / @as(f32, @floatFromInt(SPLINE_SEGMENT_DIVISIONS));

    var currentPoint = Vector2{ .x = 0, .y = 0 };
    var nextPoint = Vector2{ .x = 0, .y = 0 };
    var t: f32 = 0.0;

    var points = std.mem.zeroes([SPLINE_VERTEX_COUNT]Vector2);

    var a = [4]f32{ 0, 0, 0, 0 };
    var b = [4]f32{ 0, 0, 0, 0 };

    a[0] = (-p1.x + 3 * p2.x - 3 * p3.x + p4.x) / 6.0;
    a[1] = (3 * p1.x - 6 * p2.x + 3 * p3.x) / 6.0;
    a[2] = (-3 * p1.x + 3 * p3.x) / 6.0;
    a[3] = (p1.x + 4 * p2.x + p3.x) / 6.0;

    b[0] = (-p1.y + 3 * p2.y - 3 * p3.y + p4.y) / 6.0;
    b[1] = (3 * p1.y - 6 * p2.y + 3 * p3.y) / 6.0;
    b[2] = (-3 * p1.y + 3 * p3.y) / 6.0;
    b[3] = (p1.y + 4 * p2.y + p3.y) / 6.0;

    currentPoint.x = a[3];
    currentPoint.y = b[3];

    var i: c_int = 0;
    while (i <= SPLINE_SEGMENT_DIVISIONS) : (i += 1) {
        t = step * @as(f32, @floatFromInt(i));

        nextPoint.x = a[3] + t * (a[2] + t * (a[1] + t * a[0]));
        nextPoint.y = b[3] + t * (b[2] + t * (b[1] + t * b[0]));

        const dy = nextPoint.y - currentPoint.y;
        const dx = nextPoint.x - currentPoint.x;
        const size = (0.5 * thick) / sqrtf(dx * dx + dy * dy);

        if (i == 1) {
            points[0].x = currentPoint.x + dy * size;
            points[0].y = currentPoint.y - dx * size;
            points[1].x = currentPoint.x - dy * size;
            points[1].y = currentPoint.y + dx * size;
        }

        const idx: usize = @intCast(2 * i);
        points[idx + 1].x = nextPoint.x - dy * size;
        points[idx + 1].y = nextPoint.y + dx * size;
        points[idx].x = nextPoint.x + dy * size;
        points[idx].y = nextPoint.y - dx * size;

        currentPoint = nextPoint;
    }

    DrawTriangleStrip(&points, 2 * SPLINE_SEGMENT_DIVISIONS + 2, color);
}

// Draw spline segment: Catmull-Rom, 4 points
export fn DrawSplineSegmentCatmullRom(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, thick: f32, color: Color) callconv(.c) void {
    const step = 1.0 / @as(f32, @floatFromInt(SPLINE_SEGMENT_DIVISIONS));

    var currentPoint = p1;
    var nextPoint = Vector2{ .x = 0, .y = 0 };
    var t: f32 = 0.0;

    var points = std.mem.zeroes([SPLINE_VERTEX_COUNT]Vector2);

    var i: c_int = 0;
    while (i <= SPLINE_SEGMENT_DIVISIONS) : (i += 1) {
        t = step * @as(f32, @floatFromInt(i));

        const q0 = (-1 * t * t * t) + (2 * t * t) + (-1 * t);
        const q1 = (3 * t * t * t) + (-5 * t * t) + 2;
        const q2 = (-3 * t * t * t) + (4 * t * t) + t;
        const q3 = t * t * t - t * t;

        nextPoint.x = 0.5 * ((p1.x * q0) + (p2.x * q1) + (p3.x * q2) + (p4.x * q3));
        nextPoint.y = 0.5 * ((p1.y * q0) + (p2.y * q1) + (p3.y * q2) + (p4.y * q3));

        const dy = nextPoint.y - currentPoint.y;
        const dx = nextPoint.x - currentPoint.x;
        const size = (0.5 * thick) / sqrtf(dx * dx + dy * dy);

        if (i == 1) {
            points[0].x = currentPoint.x + dy * size;
            points[0].y = currentPoint.y - dx * size;
            points[1].x = currentPoint.x - dy * size;
            points[1].y = currentPoint.y + dx * size;
        }

        const idx: usize = @intCast(2 * i);
        points[idx + 1].x = nextPoint.x - dy * size;
        points[idx + 1].y = nextPoint.y + dx * size;
        points[idx].x = nextPoint.x + dy * size;
        points[idx].y = nextPoint.y - dx * size;

        currentPoint = nextPoint;
    }

    DrawTriangleStrip(&points, 2 * SPLINE_SEGMENT_DIVISIONS + 2, color);
}

// Draw spline segment: Quadratic Bezier, 2 points, 1 control point
export fn DrawSplineSegmentBezierQuadratic(p1: Vector2, c2: Vector2, p3: Vector2, thick: f32, color: Color) callconv(.c) void {
    const step = 1.0 / @as(f32, @floatFromInt(SPLINE_SEGMENT_DIVISIONS));

    var previous = p1;
    var current = Vector2{ .x = 0, .y = 0 };
    var t: f32 = 0.0;

    var points = std.mem.zeroes([SPLINE_VERTEX_COUNT]Vector2);

    var i: c_int = 1;
    while (i <= SPLINE_SEGMENT_DIVISIONS) : (i += 1) {
        t = step * @as(f32, @floatFromInt(i));

        const a = powf(1.0 - t, 2);
        const b = 2.0 * (1.0 - t) * t;
        const c = powf(t, 2);

        // NOTE: The easing functions aren't suitable here because they don't take a control point
        current.y = a * p1.y + b * c2.y + c * p3.y;
        current.x = a * p1.x + b * c2.x + c * p3.x;

        const dy = current.y - previous.y;
        const dx = current.x - previous.x;
        const size = 0.5 * thick / sqrtf(dx * dx + dy * dy);

        if (i == 1) {
            points[0].x = previous.x + dy * size;
            points[0].y = previous.y - dx * size;
            points[1].x = previous.x - dy * size;
            points[1].y = previous.y + dx * size;
        }

        const idx: usize = @intCast(2 * i);
        points[idx + 1].x = current.x - dy * size;
        points[idx + 1].y = current.y + dx * size;
        points[idx].x = current.x + dy * size;
        points[idx].y = current.y - dx * size;

        previous = current;
    }

    DrawTriangleStrip(&points, 2 * SPLINE_SEGMENT_DIVISIONS + 2, color);
}

// Draw spline segment: Cubic Bezier, 2 points, 2 control points
export fn DrawSplineSegmentBezierCubic(p1: Vector2, c2: Vector2, c3: Vector2, p4: Vector2, thick: f32, color: Color) callconv(.c) void {
    const step = 1.0 / @as(f32, @floatFromInt(SPLINE_SEGMENT_DIVISIONS));

    var previous = p1;
    var current = Vector2{ .x = 0, .y = 0 };
    var t: f32 = 0.0;

    var points = std.mem.zeroes([SPLINE_VERTEX_COUNT]Vector2);

    var i: c_int = 1;
    while (i <= SPLINE_SEGMENT_DIVISIONS) : (i += 1) {
        t = step * @as(f32, @floatFromInt(i));

        const a = powf(1.0 - t, 3);
        const b = 3.0 * powf(1.0 - t, 2) * t;
        const c = 3.0 * (1.0 - t) * powf(t, 2);
        const d = powf(t, 3);

        current.y = a * p1.y + b * c2.y + c * c3.y + d * p4.y;
        current.x = a * p1.x + b * c2.x + c * c3.x + d * p4.x;

        const dy = current.y - previous.y;
        const dx = current.x - previous.x;
        const size = 0.5 * thick / sqrtf(dx * dx + dy * dy);

        if (i == 1) {
            points[0].x = previous.x + dy * size;
            points[0].y = previous.y - dx * size;
            points[1].x = previous.x - dy * size;
            points[1].y = previous.y + dx * size;
        }

        const idx: usize = @intCast(2 * i);
        points[idx + 1].x = current.x - dy * size;
        points[idx + 1].y = current.y + dx * size;
        points[idx].x = current.x + dy * size;
        points[idx].y = current.y - dx * size;

        previous = current;
    }

    DrawTriangleStrip(&points, 2 * SPLINE_SEGMENT_DIVISIONS + 2, color);
}

// Get spline point for a given t [0.0f .. 1.0f], Linear
export fn GetSplinePointLinear(startPos: Vector2, endPos: Vector2, t: f32) callconv(.c) Vector2 {
    var point = Vector2{ .x = 0, .y = 0 };

    point.x = startPos.x * (1.0 - t) + endPos.x * t;
    point.y = startPos.y * (1.0 - t) + endPos.y * t;

    return point;
}

// Get spline point for a given t [0.0f .. 1.0f], B-Spline
export fn GetSplinePointBasis(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, t: f32) callconv(.c) Vector2 {
    var point = Vector2{ .x = 0, .y = 0 };

    var a = [4]f32{ 0, 0, 0, 0 };
    var b = [4]f32{ 0, 0, 0, 0 };

    a[0] = (-p1.x + 3 * p2.x - 3 * p3.x + p4.x) / 6.0;
    a[1] = (3 * p1.x - 6 * p2.x + 3 * p3.x) / 6.0;
    a[2] = (-3 * p1.x + 3 * p3.x) / 6.0;
    a[3] = (p1.x + 4 * p2.x + p3.x) / 6.0;

    b[0] = (-p1.y + 3 * p2.y - 3 * p3.y + p4.y) / 6.0;
    b[1] = (3 * p1.y - 6 * p2.y + 3 * p3.y) / 6.0;
    b[2] = (-3 * p1.y + 3 * p3.y) / 6.0;
    b[3] = (p1.y + 4 * p2.y + p3.y) / 6.0;

    point.x = a[3] + t * (a[2] + t * (a[1] + t * a[0]));
    point.y = b[3] + t * (b[2] + t * (b[1] + t * b[0]));

    return point;
}

// Get spline point for a given t [0.0f .. 1.0f], Catmull-Rom
export fn GetSplinePointCatmullRom(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, t: f32) callconv(.c) Vector2 {
    var point = Vector2{ .x = 0, .y = 0 };

    const q0 = (-1 * t * t * t) + (2 * t * t) + (-1 * t);
    const q1 = (3 * t * t * t) + (-5 * t * t) + 2;
    const q2 = (-3 * t * t * t) + (4 * t * t) + t;
    const q3 = t * t * t - t * t;

    point.x = 0.5 * ((p1.x * q0) + (p2.x * q1) + (p3.x * q2) + (p4.x * q3));
    point.y = 0.5 * ((p1.y * q0) + (p2.y * q1) + (p3.y * q2) + (p4.y * q3));

    return point;
}

// Get spline point for a given t [0.0f .. 1.0f], Quadratic Bezier
export fn GetSplinePointBezierQuadratic(startPos: Vector2, controlPos: Vector2, endPos: Vector2, t: f32) callconv(.c) Vector2 {
    var point = Vector2{ .x = 0, .y = 0 };

    const a = powf(1.0 - t, 2);
    const b = 2.0 * (1.0 - t) * t;
    const c = powf(t, 2);

    point.y = a * startPos.y + b * controlPos.y + c * endPos.y;
    point.x = a * startPos.x + b * controlPos.x + c * endPos.x;

    return point;
}

// Get spline point for a given t [0.0f .. 1.0f], Cubic Bezier
export fn GetSplinePointBezierCubic(startPos: Vector2, startControlPos: Vector2, endControlPos: Vector2, endPos: Vector2, t: f32) callconv(.c) Vector2 {
    var point = Vector2{ .x = 0, .y = 0 };

    const a = powf(1.0 - t, 3);
    const b = 3.0 * powf(1.0 - t, 2) * t;
    const c = 3.0 * (1.0 - t) * powf(t, 2);
    const d = powf(t, 3);

    point.y = a * startPos.y + b * startControlPos.y + c * endControlPos.y + d * endPos.y;
    point.x = a * startPos.x + b * startControlPos.x + c * endControlPos.x + d * endPos.x;

    return point;
}

//----------------------------------------------------------------------------------
// Module Functions Definition - Collision Detection functions
//----------------------------------------------------------------------------------

// Check if point is inside rectangle
export fn CheckCollisionPointRec(point: Vector2, rec: Rectangle) callconv(.c) bool {
    var collision = false;

    if ((point.x >= rec.x) and (point.x < (rec.x + rec.width)) and (point.y >= rec.y) and (point.y < (rec.y + rec.height))) collision = true;

    return collision;
}

// Check if point is inside circle
export fn CheckCollisionPointCircle(point: Vector2, center: Vector2, radius: f32) callconv(.c) bool {
    var collision = false;

    const distanceSquared = (point.x - center.x) * (point.x - center.x) + (point.y - center.y) * (point.y - center.y);

    if (distanceSquared <= radius * radius) collision = true;

    return collision;
}

// Check if point is inside a triangle defined by three points (p1, p2, p3)
export fn CheckCollisionPointTriangle(point: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) callconv(.c) bool {
    var collision = false;

    const alpha = ((p2.y - p3.y) * (point.x - p3.x) + (p3.x - p2.x) * (point.y - p3.y)) /
        ((p2.y - p3.y) * (p1.x - p3.x) + (p3.x - p2.x) * (p1.y - p3.y));

    const beta = ((p3.y - p1.y) * (point.x - p3.x) + (p1.x - p3.x) * (point.y - p3.y)) /
        ((p2.y - p3.y) * (p1.x - p3.x) + (p3.x - p2.x) * (p1.y - p3.y));

    const gamma = 1.0 - alpha - beta;

    if ((alpha > 0) and (beta > 0) and (gamma > 0)) collision = true;

    return collision;
}

// Check if point is within a polygon described by array of vertices
// NOTE: Based on http://jeffreythompson.org/collision-detection/poly-point.php
export fn CheckCollisionPointPoly(point: Vector2, points: [*c]const Vector2, pointCount: c_int) callconv(.c) bool {
    var collision = false;

    if (pointCount > 2) {
        var i: c_int = 0;
        var j: c_int = pointCount - 1;
        while (i < pointCount) : ({
            j = i;
            i += 1;
        }) {
            const ui: usize = @intCast(i);
            const uj: usize = @intCast(j);
            if ((points[ui].y > point.y) != (points[uj].y > point.y) and
                (point.x < (points[uj].x - points[ui].x) * (point.y - points[ui].y) / (points[uj].y - points[ui].y) + points[ui].x))
            {
                collision = !collision;
            }
        }
    }

    return collision;
}

// Check collision between two rectangles
export fn CheckCollisionRecs(rec1: Rectangle, rec2: Rectangle) callconv(.c) bool {
    var collision = false;

    if ((rec1.x < (rec2.x + rec2.width) and (rec1.x + rec1.width) > rec2.x) and
        (rec1.y < (rec2.y + rec2.height) and (rec1.y + rec1.height) > rec2.y)) collision = true;

    return collision;
}

// Check collision between two circles
export fn CheckCollisionCircles(center1: Vector2, radius1: f32, center2: Vector2, radius2: f32) callconv(.c) bool {
    var collision = false;

    const dx = center2.x - center1.x; // X distance between centers
    const dy = center2.y - center1.y; // Y distance between centers

    const distanceSquared = dx * dx + dy * dy; // Distance between centers squared
    const radiusSum = radius1 + radius2;

    collision = (distanceSquared <= (radiusSum * radiusSum));

    return collision;
}

// Check collision between circle and rectangle
// NOTE: Reviewed version to take into account corner limit case
export fn CheckCollisionCircleRec(center: Vector2, radius: f32, rec: Rectangle) callconv(.c) bool {
    var collision = false;

    const recCenterX = rec.x + rec.width / 2.0;
    const recCenterY = rec.y + rec.height / 2.0;

    const dx = fabsf(center.x - recCenterX);
    const dy = fabsf(center.y - recCenterY);

    if ((dx <= (rec.width / 2.0 + radius)) and (dy <= (rec.height / 2.0 + radius))) {
        if (dx <= (rec.width / 2.0)) {
            collision = true;
        } else if (dy <= (rec.height / 2.0)) {
            collision = true;
        } else {
            const cornerDistanceSq = (dx - rec.width / 2.0) * (dx - rec.width / 2.0) +
                (dy - rec.height / 2.0) * (dy - rec.height / 2.0);

            collision = (cornerDistanceSq <= (radius * radius));
        }
    }

    return collision;
}

// Check the collision between two lines defined by two points each, returns collision point by reference
export fn CheckCollisionLines(startPos1: Vector2, endPos1: Vector2, startPos2: Vector2, endPos2: Vector2, collisionPoint: [*c]Vector2) callconv(.c) bool {
    var collision = false;

    const rx = endPos1.x - startPos1.x;
    const ry = endPos1.y - startPos1.y;
    const sx = endPos2.x - startPos2.x;
    const sy = endPos2.y - startPos2.y;

    const div = rx * sy - ry * sx;

    if (fabsf(div) >= FLT_EPSILON) {
        const s12x = startPos2.x - startPos1.x;
        const s12y = startPos2.y - startPos1.y;

        const t = (s12x * sy - s12y * sx) / div;
        const u = (s12x * ry - s12y * rx) / div;

        if ((0.0 <= t) and (t <= 1.0) and (0.0 <= u) and (u <= 1.0)) {
            if (collisionPoint != null) {
                collisionPoint.*.x = startPos1.x + t * rx;
                collisionPoint.*.y = startPos1.y + t * ry;
            }

            collision = true;
        }
    }

    return collision;
}

// Check if point belongs to line created between two points [p1] and [p2] with defined margin in pixels [threshold]
export fn CheckCollisionPointLine(point: Vector2, p1: Vector2, p2: Vector2, threshold: c_int) callconv(.c) bool {
    var collision = false;

    const dxc = point.x - p1.x;
    const dyc = point.y - p1.y;
    const dxl = p2.x - p1.x;
    const dyl = p2.y - p1.y;
    const cross = dxc * dyl - dyc * dxl;

    if (fabsf(cross) < (@as(f32, @floatFromInt(threshold)) * fmaxf(fabsf(dxl), fabsf(dyl)))) {
        if (fabsf(dxl) >= fabsf(dyl)) {
            collision = if (dxl > 0) ((p1.x <= point.x) and (point.x <= p2.x)) else ((p2.x <= point.x) and (point.x <= p1.x));
        } else {
            collision = if (dyl > 0) ((p1.y <= point.y) and (point.y <= p2.y)) else ((p2.y <= point.y) and (point.y <= p1.y));
        }
    }

    return collision;
}

// Check if circle collides with a line created between two points [p1] and [p2]
export fn CheckCollisionCircleLine(center: Vector2, radius: f32, p1: Vector2, p2: Vector2) callconv(.c) bool {
    var collision = false;

    const dx = p1.x - p2.x;
    const dy = p1.y - p2.y;

    if ((fabsf(dx) + fabsf(dy)) <= FLT_EPSILON) {
        collision = CheckCollisionCircles(p1, 0, center, radius);
    } else {
        const lengthSQ = ((dx * dx) + (dy * dy));
        var dotProduct = (((center.x - p1.x) * (p2.x - p1.x)) + ((center.y - p1.y) * (p2.y - p1.y))) / (lengthSQ);

        if (dotProduct > 1.0) {
            dotProduct = 1.0;
        } else if (dotProduct < 0.0) {
            dotProduct = 0.0;
        }

        const dx2 = (p1.x - (dotProduct * (dx))) - center.x;
        const dy2 = (p1.y - (dotProduct * (dy))) - center.y;
        const distanceSQ = ((dx2 * dx2) + (dy2 * dy2));

        if (distanceSQ <= radius * radius) collision = true;
    }

    return collision;
}

// Get collision rectangle for two rectangles collision
export fn GetCollisionRec(rec1: Rectangle, rec2: Rectangle) callconv(.c) Rectangle {
    var overlap = Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };

    const left = if (rec1.x > rec2.x) rec1.x else rec2.x;
    const right1 = rec1.x + rec1.width;
    const right2 = rec2.x + rec2.width;
    const right = if (right1 < right2) right1 else right2;
    const top = if (rec1.y > rec2.y) rec1.y else rec2.y;
    const bottom1 = rec1.y + rec1.height;
    const bottom2 = rec2.y + rec2.height;
    const bottom = if (bottom1 < bottom2) bottom1 else bottom2;

    if ((left < right) and (top < bottom)) {
        overlap.x = left;
        overlap.y = top;
        overlap.width = right - left;
        overlap.height = bottom - top;
    }

    return overlap;
}

//----------------------------------------------------------------------------------
// Module Internal Functions Definition
//----------------------------------------------------------------------------------

// Cubic easing in-out
// NOTE: Used by DrawLineBezier() only
fn easeCubicInOut(t_in: f32, b: f32, c: f32, d: f32) f32 {
    var result: f32 = 0.0;

    var t = t_in / (0.5 * d);
    if (t < 1) {
        result = 0.5 * c * t * t * t + b;
    } else {
        t -= 2;
        result = 0.5 * c * (t * t * t + 2.0) + b;
    }

    return result;
}
