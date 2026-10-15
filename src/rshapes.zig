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
extern fn asinf(f32) f32;
extern fn atan2f(f32, f32) f32;
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
const RAD2DEG: f32 = 180.0 / PI;

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

// C `(int)` conversion of a float as compiled for x86-64 (cvttss2si): truncates toward
// zero, and NaN or out-of-range inputs yield INT_MIN instead of trapping. Degenerate
// radii (e.g. smaller than SMOOTH_CIRCLE_ERROR_RATE/2) feed NaN into segment counts.
fn cInt(v: f32) c_int {
    if (!(v >= -2147483648.0 and v < 2147483648.0)) return std.math.minInt(c_int);
    return @intFromFloat(v);
}

// texShapes.width / texShapes.height as floats (C promotes the int field to float in division)
inline fn texW() f32 {
    return @floatFromInt(texShapes.width);
}
inline fn texH() f32 {
    return @floatFromInt(texShapes.height);
}

// Shapes texture rectangle corners, normalized to texture coordinates
const ShapeUv = struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32,

    fn init(rec: Rectangle) ShapeUv {
        return .{
            .left = rec.x / texW(),
            .right = (rec.x + rec.width) / texW(),
            .top = rec.y / texH(),
            .bottom = (rec.y + rec.height) / texH(),
        };
    }
};

inline fn vertex(p: Vector2) void {
    rlVertex2f(p.x, p.y);
}

inline fn vertexUv(u: f32, v: f32, p: Vector2) void {
    rlTexCoord2f(u, v);
    rlVertex2f(p.x, p.y);
}

// Emit one RL_QUADS quad with the texture corner order shared by the circle sector
// and ring outlines: left-bottom, left-top, right-top, right-bottom
fn outlineQuad(uv: ShapeUv, a: Vector2, b: Vector2, c: Vector2, d: Vector2) void {
    vertexUv(uv.left, uv.bottom, a);
    vertexUv(uv.left, uv.top, b);
    vertexUv(uv.right, uv.top, c);
    vertexUv(uv.right, uv.bottom, d);
}

// Point at `angle` degrees and `radius` distance from `center`
inline fn polar(center: Vector2, angle: f32, radius: f32) Vector2 {
    return .{ .x = center.x + cosf(DEG2RAD * angle) * radius, .y = center.y + sinf(DEG2RAD * angle) * radius };
}

// Point at `angle` degrees and `radius` distance from the origin
inline fn polarOrigin(angle: f32, radius: f32) Vector2 {
    return .{ .x = cosf(DEG2RAD * angle) * radius, .y = sinf(DEG2RAD * angle) * radius };
}

// `a + (b - a)*t`, per component
inline fn lerp(a: Vector2, b: Vector2, t: f32) Vector2 {
    return .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t };
}

// Rotate `v` by `angle` radians (raymath Vector2Rotate)
// NOTE: Components are copied first so `v = rotate(v, a)` cannot read a half-written result
inline fn rotate(v: Vector2, angle: f32) Vector2 {
    const x = v.x;
    const y = v.y;
    const cosres = cosf(angle);
    const sinres = sinf(angle);
    return .{ .x = cosres * x - sinres * y, .y = sinres * x + cosres * y };
}

// Corner start angles of rounded rectangles: upper-left, upper-right, lower-right, lower-left
const rounded_corner_angles = [4]f32{ 180.0, 270.0, 0.0, 90.0 };

// Segments per rounded-rectangle corner that keep the error under SMOOTH_CIRCLE_ERROR_RATE
fn roundedCornerSegments(radius: f32) c_int {
    // Calculate the maximum angle between segments based on the error rate (usually 0.5f)
    const th = acosf(2 * powf(1 - SMOOTH_CIRCLE_ERROR_RATE / radius, 2) - 1);
    const segments = cInt(ceilf((2 * PI / th) / 4.0));
    return if (segments <= 0) 4 else segments;
}

// Segments for an arc from `startAngle` to `endAngle` when fewer than `minSegments` were requested
fn arcSegments(radius: f32, startAngle: f32, endAngle: f32, minSegments: c_int) c_int {
    // Calculate the maximum angle between segments based on the error rate (usually 0.5f)
    const th = acosf(2 * powf(1 - SMOOTH_CIRCLE_ERROR_RATE / radius, 2) - 1);
    const segments = cInt(ceilf((endAngle - startAngle) * (2 * PI / th) / 360.0));
    return if (segments <= 0) minSegments else segments;
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

// Draw a triangle using lines with thickness
// NOTE: Vertex must be provided in counter-clockwise order; negative thickness grows the
// outline outwards from the triangle
export fn DrawTriangleLinesEx(v1_in: Vector2, v2_in: Vector2, v3_in: Vector2, thick: f32, color: Color) callconv(.c) void {
    // The exterior points are v1-3, the interior points are v4-6, and the exterior edges are e1-3
    //
    //          v1
    //          /\
    //         /v4\
    //        //  \\
    //    e3 //    \\ e2
    //      //v5  v6\\
    //     v2========v3
    //          e1
    var v1 = v1_in;
    var v2 = v2_in;
    var v3 = v3_in;

    const e1 = Vector2{ .x = v2.x - v3.x, .y = v2.y - v3.y };
    const e2 = Vector2{ .x = v3.x - v1.x, .y = v3.y - v1.y };
    const e3 = Vector2{ .x = v1.x - v2.x, .y = v1.y - v2.y };

    const e1Length = sqrtf(e1.x * e1.x + e1.y * e1.y);
    const e2Length = sqrtf(e2.x * e2.x + e2.y * e2.y);
    const e3Length = sqrtf(e3.x * e3.x + e3.y * e3.y);

    const perimeter = e1Length + e2Length + e3Length;
    const semiperimeter = perimeter / 2.0;

    // The incenter is equidistant from each edge, which makes for an even outline
    const incenter = Vector2{
        .x = (e1Length * v1.x + e2Length * v2.x + e3Length * v3.x) / perimeter,
        .y = (e1Length * v1.y + e2Length * v2.y + e3Length * v3.y) / perimeter,
    };

    // The inradius is the radius of the biggest circle (centered on the incenter) that fits inside
    const inradius = sqrtf(((semiperimeter - e1Length) * (semiperimeter - e2Length) * (semiperimeter - e3Length)) / semiperimeter);

    // The triangle (v1, v2, v3) scaled by this around the incenter gives (v4, v5, v6)
    const scale = 1.0 - thick / inradius;

    // Just a filled-in triangle
    if (scale <= 0.0) {
        DrawTriangle(v1, v2, v3, color);
        return;
    }

    var v4 = Vector2{ .x = incenter.x + (v1.x - incenter.x) * scale, .y = incenter.y + (v1.y - incenter.y) * scale };
    var v5 = Vector2{ .x = incenter.x + (v2.x - incenter.x) * scale, .y = incenter.y + (v2.y - incenter.y) * scale };
    var v6 = Vector2{ .x = incenter.x + (v3.x - incenter.x) * scale, .y = incenter.y + (v3.y - incenter.y) * scale };

    // Swap the vertices so the winding order is correct
    if (thick < 0.0) {
        std.mem.swap(Vector2, &v1, &v4);
        std.mem.swap(Vector2, &v2, &v5);
        std.mem.swap(Vector2, &v3, &v6);
    }

    rlSetTexture(GetShapesTexture().id);
    const uv = ShapeUv.init(GetShapesTextureRectangle());

    rlBegin(RL_QUADS);
    rlColor4ub(color.r, color.g, color.b, color.a);

    // Edges 3, 1 and 2: each quad joins two exterior vertices to their interior pair
    const edges = [3][4]Vector2{ .{ v1, v2, v5, v4 }, .{ v2, v3, v6, v5 }, .{ v3, v1, v4, v6 } };
    for (edges) |edge| {
        vertexUv(uv.left, uv.top, edge[0]);
        vertexUv(uv.left, uv.bottom, edge[1]);
        vertexUv(uv.right, uv.bottom, edge[2]);
        vertexUv(uv.right, uv.top, edge[3]);
    }

    rlEnd();
    rlSetTexture(0);
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
    if ((thick > rec.width / 2) or (thick > rec.height / 2)) {
        if (rec.width >= rec.height) {
            thick = rec.height / 2;
        } else if (rec.width <= rec.height) {
            thick = rec.width / 2;
        }
    }

    if (thick > 0.0) {
        // When rec = { x, y, 8.0f, 6.0f } and thick = 2, the following
        // four rectangles are drawn ([T]op, [B]ottom, [L]eft, [R]ight):
        //
        //   TTTTTTTT
        //   TTTTTTTT
        //   LL    RR
        //   LL    RR
        //   BBBBBBBB
        //   BBBBBBBB
        //
        DrawRectangleRec(.{ .x = rec.x, .y = rec.y, .width = rec.width, .height = thick }, color);
        DrawRectangleRec(.{ .x = rec.x, .y = rec.y - thick + rec.height, .width = rec.width, .height = thick }, color);
        DrawRectangleRec(.{ .x = rec.x, .y = rec.y + thick, .width = thick, .height = rec.height - thick * 2.0 }, color);
        DrawRectangleRec(.{ .x = rec.x - thick + rec.width, .y = rec.y + thick, .width = thick, .height = rec.height - thick * 2.0 }, color);
    } else {
        // Negative thickness grows the outline outwards: with rec = { x, y, 8.0f, 6.0f }
        // and thick = -2 the [T]op/[B]ottom bars span 12 columns and [L]eft/[R]ight
        // bars sit just outside the rectangle's 6 rows
        thick *= -1.0;
        DrawRectangleRec(.{ .x = rec.x - thick, .y = rec.y - thick, .width = rec.width + thick * 2.0, .height = thick }, color);
        DrawRectangleRec(.{ .x = rec.x - thick, .y = rec.y + rec.height, .width = rec.width + thick * 2.0, .height = thick }, color);
        DrawRectangleRec(.{ .x = rec.x - thick, .y = rec.y, .width = thick, .height = rec.height }, color);
        DrawRectangleRec(.{ .x = rec.x + rec.width, .y = rec.y, .width = thick, .height = rec.height }, color);
    }
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
    if (segments < 1) segments = roundedCornerSegments(radius);

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
        if (@rem(segments, 2) == 1) {
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
export fn DrawRectangleRoundedLines(rec: Rectangle, roundness_in: f32, segments_in: c_int, color: Color) callconv(.c) void {
    var roundness = roundness_in;
    var segments = segments_in;

    // Not a rounded rectangle
    if (roundness <= 0.0) {
        DrawRectangleLines(cInt(rec.x), cInt(rec.y), cInt(rec.width), cInt(rec.height), color);
        return;
    }

    if (roundness >= 1.0) roundness = 1.0;

    // Calculate corner radius
    const radius = if (rec.width > rec.height) (rec.height * roundness) / 2 else (rec.width * roundness) / 2;
    if (radius <= 0.0) return;

    // Calculate number of segments to use for the corners
    if (segments < 1) segments = roundedCornerSegments(radius);

    const stepLength = 90.0 / @as(f32, @floatFromInt(segments));

    // Outline coordinates, inset by half a pixel so 1px lines land on pixel centers
    //
    //        P0 ------------------ P1
    //       /                        \
    //   P7 |    *P8              P9*  | P2
    //   P6 |    *P11            P10*  | P3
    //       \                        /
    //        P5 ------------------ P4
    const x0 = rec.x + radius + 0.5;
    const x1 = (rec.x + rec.width) - radius - 0.5;
    const x2 = (rec.x + rec.width) - 0.5;
    const x3 = rec.x + 0.5;

    const y0 = rec.y + 0.5;
    const y1 = rec.y + radius + 0.5;
    const y2 = (rec.y + rec.height) - radius - 0.5;
    const y3 = (rec.y + rec.height) - 0.5;

    const points = [8]Vector2{
        .{ .x = x0, .y = y0 }, // P0
        .{ .x = x1, .y = y0 }, // P1
        .{ .x = x2, .y = y1 }, // P2
        .{ .x = x2, .y = y2 }, // P3
        .{ .x = x1, .y = y3 }, // P4
        .{ .x = x0, .y = y3 }, // P5
        .{ .x = x3, .y = y2 }, // P6
        .{ .x = x3, .y = y1 }, // P7
    };

    const centers = [4]Vector2{
        .{ .x = x0, .y = y1 }, // P8
        .{ .x = x1, .y = y1 }, // P9
        .{ .x = x1, .y = y2 }, // P10
        .{ .x = x0, .y = y2 }, // P11
    };

    rlBegin(RL_LINES);
    // Draw all the 4 corners first: Upper Left Corner, Upper Right Corner, Lower Right Corner, Lower Left Corner
    for (centers, rounded_corner_angles) |center, start_angle| {
        var angle = start_angle;
        var i: c_int = 0;
        while (i < segments) : (i += 1) {
            rlColor4ub(color.r, color.g, color.b, color.a);
            vertex(polar(center, angle, radius));
            vertex(polar(center, angle + stepLength, radius));
            angle += stepLength;
        }
    }

    // And now the remaining 4 lines
    var i: usize = 0;
    while (i < points.len) : (i += 2) {
        rlColor4ub(color.r, color.g, color.b, color.a);
        vertex(points[i]);
        vertex(points[i + 1]);
    }
    rlEnd();
}

// Draw rectangle with rounded edges outline with line thickness
// NOTE: Negative thickness grows the outline outwards from the rectangle
export fn DrawRectangleRoundedLinesEx(rec_in: Rectangle, roundness_in: f32, segments_in: c_int, thick: f32, color: Color) callconv(.c) void {
    var rec = rec_in;
    var roundness = roundness_in;
    var segments = segments_in;

    // Not a rounded rectangle
    if (roundness <= 0.0) {
        DrawRectangleLinesEx(rec, thick, color);
        return;
    }

    if (roundness >= 1.0) roundness = 1.0;

    // Calculate corner radius
    const radius = if (rec.width > rec.height) (rec.height * roundness) / 2 else (rec.width * roundness) / 2;
    if (radius <= 0.0) return; // Only possible if the rectangle has 0 width or height

    var roundedOutlineThick: f32 = 0.0;
    var outerRadius: f32 = 0.0;
    var innerRadius: f32 = 0.0;
    if (thick >= 0.0) {
        outerRadius = radius;
        innerRadius = outerRadius - thick;

        // The maximum thickness the outline can have and still be rounded on the interior edge is
        // equal to the corner radius: past it, the interior of the outline is a plain rectangle
        if (innerRadius <= 0.0) {
            innerRadius = 0.0;
            roundedOutlineThick = outerRadius;

            // Draw the not-rounded portion of the outline
            DrawRectangleLinesEx(.{
                .x = rec.x + outerRadius,
                .y = rec.y + outerRadius,
                .width = rec.width - outerRadius * 2.0,
                .height = rec.height - outerRadius * 2.0,
            }, thick - outerRadius, color);
        } else {
            roundedOutlineThick = thick;
        }

        if (segments < 1) segments = roundedCornerSegments(outerRadius);
    } else {
        // Expand the rectangle
        rec.x += thick;
        rec.y += thick;
        rec.width -= thick * 2.0;
        rec.height -= thick * 2.0;

        innerRadius = radius;
        outerRadius = innerRadius - thick;
        roundedOutlineThick = -thick;

        if (segments < 1) segments = roundedCornerSegments(innerRadius);
    }

    const stepLength = 90.0 / @as(f32, @floatFromInt(segments));

    // The 16 outline points plus 4 corner centers (P16-19)
    //
    //        P0 ================== P1
    //       // P8                P9 \\
    //      //                        \\
    //  P7 // P15                  P10 \\ P2
    //    ||   *P16             P17*    ||
    //    ||                            ||
    //    || P14                   P11  ||
    //  P6 \\  *P19             P18*   // P3
    //      \\                        //
    //       \\ P13              P12 //
    //        P5 ================== P4
    const x0 = rec.x + outerRadius;
    const x1 = (rec.x + rec.width) - outerRadius;
    const x2 = rec.x + rec.width;
    const x3 = rec.x;
    const x4 = (rec.x + rec.width) - roundedOutlineThick;
    const x5 = rec.x + roundedOutlineThick;

    const y0 = rec.y;
    const y1 = rec.y + outerRadius;
    const y2 = (rec.y + rec.height) - outerRadius;
    const y3 = rec.y + rec.height;
    const y4 = rec.y + roundedOutlineThick;
    const y5 = (rec.y + rec.height) - roundedOutlineThick;

    const points = [16]Vector2{
        .{ .x = x0, .y = y0 }, // P0
        .{ .x = x1, .y = y0 }, // P1
        .{ .x = x2, .y = y1 }, // P2
        .{ .x = x2, .y = y2 }, // P3
        .{ .x = x1, .y = y3 }, // P4
        .{ .x = x0, .y = y3 }, // P5
        .{ .x = x3, .y = y2 }, // P6
        .{ .x = x3, .y = y1 }, // P7
        .{ .x = x0, .y = y4 }, // P8
        .{ .x = x1, .y = y4 }, // P9
        .{ .x = x4, .y = y1 }, // P10
        .{ .x = x4, .y = y2 }, // P11
        .{ .x = x1, .y = y5 }, // P12
        .{ .x = x0, .y = y5 }, // P13
        .{ .x = x5, .y = y2 }, // P14
        .{ .x = x5, .y = y1 }, // P15
    };

    const centers = [4]Vector2{
        .{ .x = x0, .y = y1 }, // P16
        .{ .x = x1, .y = y1 }, // P17
        .{ .x = x1, .y = y2 }, // P18
        .{ .x = x0, .y = y2 }, // P19
    };

    rlSetTexture(GetShapesTexture().id);
    const uv = ShapeUv.init(GetShapesTextureRectangle());

    rlBegin(RL_QUADS);

    // Draw all the 4 corners first: Upper Left Corner, Upper Right Corner, Lower Right Corner, Lower Left Corner
    for (centers, rounded_corner_angles) |center, start_angle| {
        var angle = start_angle;
        var i: c_int = 0;
        while (i < segments) : (i += 1) {
            rlColor4ub(color.r, color.g, color.b, color.a);
            vertexUv(uv.left, uv.top, polar(center, angle, innerRadius));
            vertexUv(uv.right, uv.top, polar(center, angle + stepLength, innerRadius));
            vertexUv(uv.right, uv.bottom, polar(center, angle + stepLength, outerRadius));
            vertexUv(uv.left, uv.bottom, polar(center, angle, outerRadius));
            angle += stepLength;
        }
    }

    // Upper, right, lower and left rectangles
    const sides = [4][4]usize{ .{ 0, 8, 9, 1 }, .{ 2, 10, 11, 3 }, .{ 13, 5, 4, 12 }, .{ 15, 7, 6, 14 } };
    for (sides) |side| {
        rlColor4ub(color.r, color.g, color.b, color.a);
        vertexUv(uv.left, uv.top, points[side[0]]);
        vertexUv(uv.left, uv.bottom, points[side[1]]);
        vertexUv(uv.right, uv.bottom, points[side[2]]);
        vertexUv(uv.right, uv.top, points[side[3]]);
    }

    rlEnd();
    rlSetTexture(0);
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
// NOTE: Negative thickness grows the outline outwards from the polygon
export fn DrawPolyLinesEx(center: Vector2, sides_in: c_int, radius: f32, rotation: f32, thick: f32, color: Color) callconv(.c) void {
    var sides = sides_in;
    if (sides < 3) sides = 3;
    var centralAngle = rotation * DEG2RAD;
    const exteriorAngle = 360.0 / @as(f32, @floatFromInt(sides)) * DEG2RAD;
    const apothem = radius * cosf(DEG2RAD * 180.0 / @as(f32, @floatFromInt(sides)));

    // Scale the thickness from the apothem to the circumradius so edges are `thick` wide
    const outerRadius = if (thick >= 0.0) radius else radius + -thick * (radius / apothem);
    const innerRadius = if (thick >= 0.0) fmaxf(0.0, radius - thick * (radius / apothem)) else radius;

    rlSetTexture(GetShapesTexture().id);
    const shapeRect = GetShapesTextureRectangle();

    rlBegin(RL_QUADS);
    var i: c_int = 0;
    while (i < sides) : (i += 1) {
        rlColor4ub(color.r, color.g, color.b, color.a);
        const nextAngle = centralAngle + exteriorAngle;

        rlTexCoord2f(shapeRect.x / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(centralAngle) * outerRadius, center.y + sinf(centralAngle) * outerRadius);

        rlTexCoord2f(shapeRect.x / texW(), shapeRect.y / texH());
        rlVertex2f(center.x + cosf(centralAngle) * innerRadius, center.y + sinf(centralAngle) * innerRadius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), (shapeRect.y + shapeRect.height) / texH());
        rlVertex2f(center.x + cosf(nextAngle) * innerRadius, center.y + sinf(nextAngle) * innerRadius);

        rlTexCoord2f((shapeRect.x + shapeRect.width) / texW(), shapeRect.y / texH());
        rlVertex2f(center.x + cosf(nextAngle) * outerRadius, center.y + sinf(nextAngle) * outerRadius);

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
export fn DrawCircleSector(center: Vector2, radius: f32, startAngle_in: f32, endAngle_in: f32, segments_in: c_int, color: Color) callconv(.c) void {
    var startAngle = startAngle_in;
    var endAngle = endAngle_in;
    var segments = segments_in;

    if (startAngle == endAngle) return;
    if (radius <= 0.0) return; // There's nothing to draw (also avoid div by zero)

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) std.mem.swap(f32, &startAngle, &endAngle);

    // Drawing a whole circle, things get weird without limiting the circle to 360 degrees
    if (endAngle - startAngle >= 360.0) endAngle = startAngle + 360.0;

    const minSegments = cInt(ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) segments = arcSegments(radius, startAngle, endAngle, minSegments);

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
export fn DrawCircleSectorLines(center: Vector2, radius: f32, startAngle_in: f32, endAngle_in: f32, segments_in: c_int, color: Color) callconv(.c) void {
    var startAngle = startAngle_in;
    var endAngle = endAngle_in;
    var segments = segments_in;

    if (startAngle == endAngle) return;
    if (radius <= 0.0) return; // There's nothing to draw (also avoid div by zero)

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) std.mem.swap(f32, &startAngle, &endAngle);

    // Drawing a whole circle, things get weird without limiting the circle to 360 degrees
    var showCapLines = true;
    if (endAngle - startAngle >= 360.0) {
        showCapLines = false;
        endAngle = startAngle + 360.0;
    }

    const minSegments = cInt(ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) segments = arcSegments(radius, startAngle, endAngle, minSegments);

    const stepLength = (endAngle - startAngle) / @as(f32, @floatFromInt(segments));
    var angle = startAngle;

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

// Draw a piece of a circle outlines with line thickness
// NOTE: Negative thickness grows the outline outwards from the circle sector
export fn DrawCircleSectorLinesEx(center: Vector2, radius: f32, startAngle_in: f32, endAngle_in: f32, segments_in: c_int, thick: f32, color: Color) callconv(.c) void {
    var startAngle = startAngle_in;
    var endAngle = endAngle_in;
    var segments = segments_in;

    if (startAngle == endAngle) return;
    if (radius <= 0.0) return; // There's nothing to draw (also avoid div by zero)

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) std.mem.swap(f32, &startAngle, &endAngle);

    // Drawing a whole circle, things get weird without limiting the circle to 360 degrees
    var showCapLines = true;
    if (endAngle - startAngle >= 360.0) {
        showCapLines = thick >= 0.0;
        endAngle = startAngle + 360.0;
    }

    const minSegments = cInt(ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) segments = arcSegments(radius, startAngle, endAngle, minSegments);

    const fsegments: f32 = @floatFromInt(segments);
    const stepLength = (endAngle - startAngle) / fsegments;

    // The outline is drawn in 3 pieces: the arc outline, cap 1 (along `startAngle`) and
    // cap 2 (along `endAngle`). Each cap is a quad S0 (the center), C0, C1, C2 for cap 1
    // and S0, C5, C4, C3 for cap 2:
    //   C2/C5 lie on the arc's inner edge at `startAngle`/`endAngle`
    //   C1/C4 lie on the arc's inner edge, `thick` pixels perpendicular from the cap edges
    //   C0/C3 are the second point shared by the caps (S1), where their inner edges meet;
    //   when S1 falls outside the arc they become the points where those edges cross it
    // With negative `thick` the same vertices lie outside the circle instead.

    // We are not drawing a circle, we are drawing an n-sided polygon
    // So, we need to adjust the outline thickness of the "circle" for it to look correct with fewer segments
    const apothem = radius * cosf(DEG2RAD * ((endAngle - startAngle) / 2.0) / fsegments);
    const radiusThick = thick * (radius / apothem);

    var outerRadius = radius;
    var innerRadius = radius - radiusThick;

    if (thick >= 0.0) {
        if (thick >= innerRadius) {
            DrawCircleSector(center, radius, startAngle, endAngle, segments, color);
            return;
        }
    } else {
        std.mem.swap(f32, &outerRadius, &innerRadius);
    }

    // Cap 1 vertices
    var c0 = Vector2{ .x = 0, .y = 0 };
    var c1 = Vector2{ .x = 0, .y = 0 };
    var c2 = Vector2{ .x = 0, .y = 0 };

    // Cap 2 vertices
    var c3 = Vector2{ .x = 0, .y = 0 };
    var c4 = Vector2{ .x = 0, .y = 0 };
    var c5 = Vector2{ .x = 0, .y = 0 };

    // The number of angle steps that come before C1 (from `startAngle`, counter clockwise)
    var stepsBeforeC1: c_int = 0;
    var s1OutsideOfCircle = false;
    // The number of angle steps that come before C0, only used if S1 is outside of the circle
    var stepsBeforeC0: c_int = 0;

    if (showCapLines) {
        if (thick >= 0.0) {
            c2 = polar(center, startAngle, innerRadius);
            c5 = polar(center, endAngle, innerRadius);

            // C1 and C4 lie on the inner (polygon) edge, `thick` pixels perpendicularly
            // from the `startAngle` and `endAngle` edges
            const c1Angle = RAD2DEG * asinf(thick / innerRadius);

            // There are more segments before C1 than there are segments being drawn,
            // so the whole circle sector must be covered
            if (c1Angle / stepLength >= fsegments) {
                DrawCircleSector(center, radius, startAngle, endAngle, segments, color);
                return;
            }

            // Done after the previous check in case `stepLength` is really small and
            // dividing by it produces a very large number
            stepsBeforeC1 = cInt(c1Angle / stepLength);

            // The angles of the outline vertices before and after C1
            const vertexAngleBeforeC1 = stepLength * @as(f32, @floatFromInt(stepsBeforeC1));
            const vertexAngleAfterC1 = stepLength * @as(f32, @floatFromInt(stepsBeforeC1 + 1));

            // In a frame of reference with `center` at the origin and `startAngle` at 0
            // degrees, C1 is where the outline segment p1->p2 crosses y = `thick`
            const p1 = polarOrigin(vertexAngleBeforeC1, innerRadius);
            const p2 = polarOrigin(vertexAngleAfterC1, innerRadius);
            const t = (p1.y - thick) / (p1.y - p2.y);

            c1 = lerp(polar(center, startAngle + vertexAngleBeforeC1, innerRadius), polar(center, startAngle + vertexAngleAfterC1, innerRadius), t);
            c4 = lerp(polar(center, endAngle - vertexAngleBeforeC1, innerRadius), polar(center, endAngle - vertexAngleAfterC1, innerRadius), t);

            // The caps are always parallel to `startAngle` and `endAngle`, so S1 sits on the
            // bisector, `s1Length` away from the center
            const innerAngleBetweenCapEnds = ((endAngle - 90.0) - (startAngle + 90.0)) / 2.0;
            const s1Length = thick / cosf(DEG2RAD * innerAngleBetweenCapEnds);

            if ((innerAngleBetweenCapEnds < 90.0) and (s1Length <= innerRadius)) {
                // S1 is inside of the circle
                c0 = polar(center, (endAngle + startAngle) / 2.0, s1Length);
                c3 = c0;

                // raymath Vector2Angle() of C1 and S1 around the center
                const a = Vector2{ .x = c1.x - center.x, .y = c1.y - center.y };
                const b = Vector2{ .x = c0.x - center.x, .y = c0.y - center.y };
                const dot = a.x * b.x + a.y * b.y;
                const det = a.x * b.y - a.y * b.x;

                // If C1 and C4 are on the wrong side of S1, the whole circle sector is covered
                if (atan2f(det, dot) < 0.0) {
                    DrawCircleSector(center, radius, startAngle, endAngle, segments, color);
                    return;
                }
            } else {
                // S1 is outside of the circle: find C0 and C3, where the caps' inner edges
                // cross the outline, the same way C1 and C4 were found
                if (endAngle - startAngle <= 180.0) {
                    DrawCircleSector(center, radius, startAngle, endAngle, segments, color);
                    return;
                }

                s1OutsideOfCircle = true;

                stepsBeforeC0 = cInt((180.0 + RAD2DEG * asinf(thick / -innerRadius)) / stepLength);

                const vertexAngleBeforeC0 = stepLength * @as(f32, @floatFromInt(stepsBeforeC0));
                const vertexAngleAfterC0 = stepLength * @as(f32, @floatFromInt(stepsBeforeC0 + 1));

                const q1 = polarOrigin(vertexAngleBeforeC0, innerRadius);
                const q2 = polarOrigin(vertexAngleAfterC0, innerRadius);
                const tC0 = (q1.y - thick) / (q1.y - q2.y);

                c0 = lerp(polar(center, startAngle + vertexAngleBeforeC0, innerRadius), polar(center, startAngle + vertexAngleAfterC0, innerRadius), tC0);
                c3 = lerp(polar(center, endAngle - vertexAngleBeforeC0, innerRadius), polar(center, endAngle - vertexAngleAfterC0, innerRadius), tC0);
            }
        } else {
            const outerAngleBetweenCapEnds = ((endAngle + 90.0) - (startAngle - 90.0)) / 2.0;
            const s1Length = thick / cosf(DEG2RAD * outerAngleBetweenCapEnds);
            c0 = polar(center, 180.0 + (endAngle + startAngle) / 2.0, s1Length);
            c3 = c0;

            c2 = polar(center, startAngle, outerRadius);
            c5 = polar(center, endAngle, outerRadius);

            // Change the frame of reference so that `center` is the origin and `startAngle` is 0 degrees
            const toStart = -DEG2RAD * startAngle;
            const c0Translated = rotate(.{ .x = c0.x - center.x, .y = c0.y - center.y }, toStart);
            var circleVertex1 = rotate(.{ .x = c2.x - center.x, .y = c2.y - center.y }, toStart);
            const circleVertex2 = rotate(polarOrigin(startAngle + stepLength, outerRadius), toStart);

            // Where the line through `circleVertex1` and `circleVertex2` crosses the
            // horizontal line through `c0Translated`
            var rise = circleVertex1.y - circleVertex2.y;
            var run = circleVertex1.x - circleVertex2.x;
            const c1Rise = c0Translated.y - circleVertex1.y;
            const c1Run = (c1Rise / rise) * run;
            const c1DistanceFromC0 = (circleVertex1.x + c1Run) - c0Translated.x;

            c1 = .{ .x = c0.x + cosf(DEG2RAD * startAngle) * c1DistanceFromC0, .y = c0.y + sinf(DEG2RAD * startAngle) * c1DistanceFromC0 };
            c4 = .{ .x = c0.x + cosf(DEG2RAD * endAngle) * c1DistanceFromC0, .y = c0.y + sinf(DEG2RAD * endAngle) * c1DistanceFromC0 };

            if (c1DistanceFromC0 < 0.0) {
                // The caps are intersecting each other
                var circleVertex3 = rotate(.{ .x = c5.x - center.x, .y = c5.y - center.y }, toStart);
                var circleVertex4 = rotate(polarOrigin(endAngle - stepLength, outerRadius), toStart);

                // `startAngle` is 0 degrees within this frame of reference,
                // so C1 just goes horizontally out from C0
                var c1Translated = Vector2{ .x = c0Translated.x + c1DistanceFromC0, .y = c0Translated.y };

                // Make `circleVertex2` the origin
                circleVertex1.x -= circleVertex2.x;
                circleVertex1.y -= circleVertex2.y;
                circleVertex3.x -= circleVertex2.x;
                circleVertex3.y -= circleVertex2.y;
                circleVertex4.x -= circleVertex2.x;
                circleVertex4.y -= circleVertex2.y;
                c1Translated.x -= circleVertex2.x;
                c1Translated.y -= circleVertex2.y;

                // Make the line between `circleVertex1` and `circleVertex2` a horizontal line
                const theta = atan2f(circleVertex1.y, circleVertex1.x);
                circleVertex1 = rotate(circleVertex1, -theta);
                circleVertex3 = rotate(circleVertex3, -theta);
                circleVertex4 = rotate(circleVertex4, -theta);
                c1Translated = rotate(c1Translated, -theta);

                // Where the line through `circleVertex3` and `circleVertex4` crosses the
                // segment from `circleVertex1` to `c1Translated`
                rise = circleVertex3.y - circleVertex4.y;
                run = circleVertex3.x - circleVertex4.x;
                const targetRise = -circleVertex3.y;
                const targetX = circleVertex3.x + (targetRise / rise) * run;

                const t = (c1Translated.x - targetX) / (c1Translated.x - circleVertex1.x);

                const crossing = lerp(c1, c2, t);
                c0 = crossing;
                c1 = crossing;
                c3 = crossing;
                c4 = crossing;
            }

            // Swap vertices to correct the winding order
            std.mem.swap(Vector2, &c0, &c2);
            std.mem.swap(Vector2, &c3, &c5);
        }
    }

    rlSetTexture(GetShapesTexture().id);
    const uv = ShapeUv.init(GetShapesTextureRectangle());

    rlBegin(RL_QUADS);
    rlColor4ub(color.r, color.g, color.b, color.a);

    // Draw the circle outline
    var angle = startAngle;
    var i: c_int = 0;
    while (i < segments) : (i += 1) {
        outlineQuad(uv, polar(center, angle, outerRadius), polar(center, angle, innerRadius), polar(center, angle + stepLength, innerRadius), polar(center, angle + stepLength, outerRadius));
        angle += stepLength;
    }

    // Draw the caps
    if (showCapLines) {
        outlineQuad(uv, center, c0, c1, c2);
        outlineQuad(uv, center, c5, c4, c3);

        // Some extra work may be needed when `thick` is positive
        if (thick >= 0.0) {
            // Fill in the gaps between each cap and the circle outline, using quads made
            // of pairs of outline vertices
            if (stepsBeforeC1 > 0) {
                angle = 0;
                i = 0;
                while (i < @divTrunc(stepsBeforeC1, 2)) : (i += 1) {
                    outlineQuad(uv, c1, polar(center, startAngle + (angle + stepLength * 2.0), innerRadius), polar(center, startAngle + (angle + stepLength), innerRadius), polar(center, startAngle + angle, innerRadius));
                    outlineQuad(uv, c4, polar(center, endAngle - angle, innerRadius), polar(center, endAngle - (angle + stepLength), innerRadius), polar(center, endAngle - (angle + stepLength * 2.0), innerRadius));
                    angle += stepLength * 2.0;
                }

                // Draw the last segment if there's an odd number of them
                if (@rem(stepsBeforeC1, 2) == 1) {
                    outlineQuad(uv, c1, c1, polar(center, startAngle + (angle + stepLength), innerRadius), polar(center, startAngle + angle, innerRadius));
                    outlineQuad(uv, c4, c4, polar(center, endAngle - angle, innerRadius), polar(center, endAngle - (angle + stepLength), innerRadius));
                }
            }

            // Fill in the gap between C0, C3 and the circle outline
            if (s1OutsideOfCircle) {
                var verticesBetweenC0andC3 = (segments - stepsBeforeC0 * 2) - 1;
                const afterC0: f32 = @floatFromInt(stepsBeforeC0 + 1);

                if (verticesBetweenC0andC3 == 0) {
                    // No gap to fill
                    outlineQuad(uv, center, center, c3, c0);
                } else {
                    // Triangles touching C0 and C3
                    outlineQuad(uv, center, center, polar(center, startAngle + stepLength * afterC0, innerRadius), c0);
                    outlineQuad(uv, center, center, c3, polar(center, endAngle - stepLength * afterC0, innerRadius));

                    // Triangles between the previous two
                    verticesBetweenC0andC3 -= 1;
                    angle = startAngle + stepLength * afterC0;
                    i = 0;
                    while (i < @divTrunc(verticesBetweenC0andC3, 2)) : (i += 1) {
                        outlineQuad(uv, center, polar(center, angle + stepLength * 2.0, innerRadius), polar(center, angle + stepLength, innerRadius), polar(center, angle, innerRadius));
                        angle += stepLength * 2.0;
                    }

                    if (@rem(verticesBetweenC0andC3, 2) == 1) {
                        outlineQuad(uv, center, center, polar(center, angle + stepLength, innerRadius), polar(center, angle, innerRadius));
                    }
                }
            }
        }
    }
    rlEnd();

    rlSetTexture(0);
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

// Draw ellipse outline with line thickness
// NOTE: Negative thickness grows the outline outwards from the ellipse
export fn DrawEllipseLinesEx(center: Vector2, radiusH: f32, radiusV: f32, thick: f32, color: Color) callconv(.c) void {
    var outerRadiusH = radiusH;
    var innerRadiusH = radiusH - thick;
    var outerRadiusV = radiusV;
    var innerRadiusV = radiusV - thick;

    if (thick >= 0.0) {
        // Just a filled-in ellipse
        if ((innerRadiusH <= 0.0) or (innerRadiusV <= 0.0)) {
            DrawEllipseV(center, radiusH, radiusV, color);
            return;
        }
    } else {
        // The outline is growing outside of the ellipse, so swap the inner and outer radius
        std.mem.swap(f32, &outerRadiusH, &innerRadiusH);
        std.mem.swap(f32, &outerRadiusV, &innerRadiusV);
    }

    rlSetTexture(GetShapesTexture().id);
    const uv = ShapeUv.init(GetShapesTextureRectangle());

    rlBegin(RL_QUADS);
    rlColor4ub(color.r, color.g, color.b, color.a);

    var i: c_int = 0;
    while (i < 360) : (i += 10) {
        const angle: f32 = @floatFromInt(i);
        const next: f32 = @floatFromInt(i + 10);

        vertexUv(uv.left, uv.top, .{ .x = center.x + cosf(DEG2RAD * angle) * innerRadiusH, .y = center.y + sinf(DEG2RAD * angle) * innerRadiusV });
        vertexUv(uv.left, uv.bottom, .{ .x = center.x + cosf(DEG2RAD * next) * innerRadiusH, .y = center.y + sinf(DEG2RAD * next) * innerRadiusV });
        vertexUv(uv.right, uv.bottom, .{ .x = center.x + cosf(DEG2RAD * next) * outerRadiusH, .y = center.y + sinf(DEG2RAD * next) * outerRadiusV });
        vertexUv(uv.right, uv.top, .{ .x = center.x + cosf(DEG2RAD * angle) * outerRadiusH, .y = center.y + sinf(DEG2RAD * angle) * outerRadiusV });
    }
    rlEnd();

    rlSetTexture(0);
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
    if (outerRadius < innerRadius) std.mem.swap(f32, &outerRadius, &innerRadius);

    if (outerRadius <= 0.0) return; // There's nothing to draw (also avoid div by zero)

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) std.mem.swap(f32, &startAngle, &endAngle);

    // Drawing a whole circle, things get weird without limiting the circle to 360 degrees
    if (endAngle - startAngle >= 360.0) endAngle = startAngle + 360.0;

    const minSegments = cInt(ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) segments = arcSegments(outerRadius, startAngle, endAngle, minSegments);

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
    if (outerRadius < innerRadius) std.mem.swap(f32, &outerRadius, &innerRadius);

    if (outerRadius <= 0.0) return; // There's nothing to draw (also avoid div by zero)

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) std.mem.swap(f32, &startAngle, &endAngle);

    // Drawing a whole circle, things get weird without limiting the circle to 360 degrees
    var showCapLines = true;
    if (endAngle - startAngle >= 360.0) {
        showCapLines = false;
        endAngle = startAngle + 360.0;
    }

    const minSegments = cInt(ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) segments = arcSegments(outerRadius, startAngle, endAngle, minSegments);

    if (innerRadius <= 0.0) {
        DrawCircleSectorLines(center, outerRadius, startAngle, endAngle, segments, color);
        return;
    }

    const stepLength = (endAngle - startAngle) / @as(f32, @floatFromInt(segments));
    var angle = startAngle;

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

// Draw ring outline with line thickness
// NOTE: Negative thickness grows the outline outwards from the ring
export fn DrawRingLinesEx(center: Vector2, innerRadius_in: f32, outerRadius_in: f32, startAngle_in: f32, endAngle_in: f32, segments_in: c_int, thick: f32, color: Color) callconv(.c) void {
    var innerRadius = innerRadius_in;
    var outerRadius = outerRadius_in;
    var startAngle = startAngle_in;
    var endAngle = endAngle_in;
    var segments = segments_in;

    if (startAngle == endAngle) return;

    // Function expects (outerRadius > innerRadius)
    if (outerRadius < innerRadius) std.mem.swap(f32, &outerRadius, &innerRadius);

    if (outerRadius <= 0.0) return; // There's nothing to draw (also avoid div by zero)

    // Function expects (endAngle > startAngle)
    if (endAngle < startAngle) std.mem.swap(f32, &startAngle, &endAngle);

    // Drawing a whole circle, things get weird without limiting the circle to 360 degrees
    var showCapLines = true;
    if (endAngle - startAngle >= 360.0) {
        showCapLines = thick >= 0.0;
        endAngle = startAngle + 360.0;
    }

    const minSegments = cInt(ceilf((endAngle - startAngle) / 90));

    if (segments < minSegments) segments = arcSegments(outerRadius, startAngle, endAngle, minSegments);

    const fsegments: f32 = @floatFromInt(segments);
    const stepLength = (endAngle - startAngle) / fsegments;

    // We are not drawing a circle, we are drawing an n-sided polygon
    // So, we need to adjust the outline thickness of the "circle" for it to look correct with fewer segments
    const apothem = outerRadius * cosf(DEG2RAD * ((endAngle - startAngle) / 2.0) / fsegments);
    const radiusThick = thick * (outerRadius / apothem);

    // Two arc outlines are drawn, so there are 4 radii, from farthest to closest to the center:
    // outerOuterRadius, innerOuterRadius, outerInnerRadius, innerInnerRadius
    var innerOuterRadius: f32 = 0.0;
    var outerOuterRadius: f32 = 0.0;
    var innerInnerRadius: f32 = 0.0;
    var outerInnerRadius: f32 = 0.0;

    if (thick >= 0.0) {
        innerRadius = fmaxf(0.0, innerRadius);

        // Just a filled-in ring
        if (radiusThick > (outerRadius - innerRadius) / 2.0) {
            DrawRing(center, innerRadius, outerRadius, startAngle, endAngle, segments, color);
            return;
        }

        innerInnerRadius = innerRadius;
        outerInnerRadius = innerInnerRadius + radiusThick;

        outerOuterRadius = outerRadius;
        innerOuterRadius = outerOuterRadius - radiusThick;
    } else {
        // Just a circle sector outline
        if (innerRadius <= 0.0) {
            DrawCircleSectorLinesEx(center, outerRadius, startAngle, endAngle, segments, thick, color);
            return;
        }

        outerInnerRadius = innerRadius;
        innerInnerRadius = fmaxf(0.0, outerInnerRadius + radiusThick);

        innerOuterRadius = outerRadius;
        outerOuterRadius = innerOuterRadius - radiusThick;
    }

    // For positive `thick` values
    var stepsBeforeInner: c_int = 0;
    var stepsBeforeOuter: c_int = 0;
    var tInner: f32 = 0.0;
    var tOuter: f32 = 0.0;
    var innerAnglesCrossEachOther = false;

    // For negative `thick` values
    var caps: NegativeRingCaps = undefined;

    if (showCapLines) {
        if (thick >= 0.0) {
            // The angle of the arc that has `thick` length along the inner and outer radii
            const cap1InnerAngleEnd = RAD2DEG * (thick / outerInnerRadius);
            const cap1OuterAngleEnd = RAD2DEG * (thick / innerOuterRadius);

            // Just a filled-in ring
            if (endAngle - startAngle < cap1OuterAngleEnd * 2.0) {
                DrawRing(center, innerRadius, outerRadius, startAngle, endAngle, segments, color);
                return;
            }

            if (endAngle - startAngle < cap1InnerAngleEnd * 2.0) innerAnglesCrossEachOther = true;

            stepsBeforeInner = cInt(cap1InnerAngleEnd / stepLength);
            stepsBeforeOuter = cInt(cap1OuterAngleEnd / stepLength);

            // With `center` as the origin and the cap's end angle at 0 degrees, the cap end
            // crosses the outline segment where 'y' is 0: solve for its lerp 't'
            tInner = capEndLerp(stepsBeforeInner, stepLength, cap1InnerAngleEnd, outerInnerRadius);
            tOuter = capEndLerp(stepsBeforeOuter, stepLength, cap1OuterAngleEnd, innerOuterRadius);
        } else {
            caps = NegativeRingCaps.init(center, startAngle, endAngle, stepLength, thick, innerInnerRadius, outerOuterRadius);
        }
    }

    var angle = startAngle;

    rlSetTexture(GetShapesTexture().id);
    const uv = ShapeUv.init(GetShapesTextureRectangle());

    rlBegin(RL_QUADS);
    rlColor4ub(color.r, color.g, color.b, color.a);

    var i: c_int = 0;
    while (i < segments) : (i += 1) {
        // `innerRadius` outline
        outlineQuad(uv, polar(center, angle, outerInnerRadius), polar(center, angle, innerInnerRadius), polar(center, angle + stepLength, innerInnerRadius), polar(center, angle + stepLength, outerInnerRadius));
        // `outerRadius` outline
        outlineQuad(uv, polar(center, angle, outerOuterRadius), polar(center, angle, innerOuterRadius), polar(center, angle + stepLength, innerOuterRadius), polar(center, angle + stepLength, outerOuterRadius));
        angle += stepLength;
    }

    if (showCapLines) {
        if (thick >= 0.0) {
            angle = 0.0;

            i = 0;
            while (i < stepsBeforeOuter) : (i += 1) {
                // Cap 1
                outlineQuad(uv, polar(center, startAngle + angle, outerInnerRadius), polar(center, startAngle + angle + stepLength, outerInnerRadius), polar(center, startAngle + angle + stepLength, innerOuterRadius), polar(center, startAngle + angle, innerOuterRadius));
                // Cap 2
                outlineQuad(uv, polar(center, endAngle - angle, outerInnerRadius), polar(center, endAngle - angle, innerOuterRadius), polar(center, endAngle - angle - stepLength, innerOuterRadius), polar(center, endAngle - angle - stepLength, outerInnerRadius));
                angle += stepLength;
            }

            // We've already moved `stepsBeforeOuter` steps from each end
            const totalStepsLeft = segments - stepsBeforeOuter * 2;
            const innerStepsLeft = stepsBeforeInner - stepsBeforeOuter;
            const innerStepsLeftF: f32 = @floatFromInt(innerStepsLeft);
            const innerStepsLeftNextF: f32 = @floatFromInt(innerStepsLeft + 1);

            // Cap 1
            const cap1OuterVertexBeforeEnd = polar(center, startAngle + angle, innerOuterRadius);
            const cap1OuterVertexAfterEnd = polar(center, startAngle + angle + stepLength, innerOuterRadius);
            const cap1InnerVertexBeforeEnd = polar(center, startAngle + angle + innerStepsLeftF * stepLength, outerInnerRadius);
            const cap1InnerVertexAfterEnd = polar(center, startAngle + angle + innerStepsLeftNextF * stepLength, outerInnerRadius);
            const cap1InnerVertexEnd = lerp(cap1InnerVertexBeforeEnd, cap1InnerVertexAfterEnd, tInner);
            const cap1OuterVertexEnd = lerp(cap1OuterVertexBeforeEnd, cap1OuterVertexAfterEnd, tOuter);

            // Cap 2
            const cap2OuterVertexBeforeEnd = polar(center, endAngle - angle, innerOuterRadius);
            const cap2OuterVertexAfterEnd = polar(center, endAngle - angle - stepLength, innerOuterRadius);
            const cap2InnerVertexBeforeEnd = polar(center, endAngle - angle - innerStepsLeftF * stepLength, outerInnerRadius);
            const cap2InnerVertexAfterEnd = polar(center, endAngle - angle - innerStepsLeftNextF * stepLength, outerInnerRadius);
            const cap2InnerVertexEnd = lerp(cap2InnerVertexBeforeEnd, cap2InnerVertexAfterEnd, tInner);
            const cap2OuterVertexEnd = lerp(cap2OuterVertexBeforeEnd, cap2OuterVertexAfterEnd, tOuter);

            const stepsCount = if (innerAnglesCrossEachOther) @divTrunc(totalStepsLeft, 2) else innerStepsLeft;

            // Iterate over pairs of steps
            i = 0;
            while (i < @divTrunc(stepsCount, 2)) : (i += 1) {
                // Cap 1
                outlineQuad(uv, cap1OuterVertexBeforeEnd, polar(center, startAngle + angle, outerInnerRadius), polar(center, startAngle + angle + stepLength, outerInnerRadius), polar(center, startAngle + angle + stepLength * 2.0, outerInnerRadius));
                // Cap 2
                outlineQuad(uv, cap2OuterVertexBeforeEnd, polar(center, endAngle - angle - stepLength * 2.0, outerInnerRadius), polar(center, endAngle - angle - stepLength, outerInnerRadius), polar(center, endAngle - angle, outerInnerRadius));
                angle += stepLength * 2.0;
            }

            // Handle the last step if there's an odd amount
            if (@rem(stepsCount, 2) == 1) {
                // Cap 1
                outlineQuad(uv, cap1OuterVertexBeforeEnd, cap1OuterVertexBeforeEnd, polar(center, startAngle + angle, outerInnerRadius), polar(center, startAngle + angle + stepLength, outerInnerRadius));
                // Cap 2
                outlineQuad(uv, cap2OuterVertexBeforeEnd, cap2OuterVertexBeforeEnd, polar(center, endAngle - angle - stepLength, outerInnerRadius), polar(center, endAngle - angle, outerInnerRadius));
                angle += stepLength;
            }

            if (innerAnglesCrossEachOther) {
                // The `*InnerVertexEnd` vertices went past each other, so the cap edges are
                // cut where the line cap1InnerVertexEnd->cap1OuterVertexEnd crosses the line
                // cap2InnerVertexEnd->cap2OuterVertexEnd, keeping the outline from intersecting itself

                // Make `cap1InnerVertexEnd` the origin and the angle to `cap1OuterVertexEnd` 0 degrees
                const tempCap1OuterVertexEnd = Vector2{ .x = cap1OuterVertexEnd.x - cap1InnerVertexEnd.x, .y = cap1OuterVertexEnd.y - cap1InnerVertexEnd.y };
                const tempCap2InnerVertexEnd = Vector2{ .x = cap2InnerVertexEnd.x - cap1InnerVertexEnd.x, .y = cap2InnerVertexEnd.y - cap1InnerVertexEnd.y };
                const tempCap2OuterVertexEnd = Vector2{ .x = cap2OuterVertexEnd.x - cap1InnerVertexEnd.x, .y = cap2OuterVertexEnd.y - cap1InnerVertexEnd.y };

                // Only the rotated 'y' coordinates are needed
                const rotateBy = -atan2f(tempCap1OuterVertexEnd.y, tempCap1OuterVertexEnd.x);
                const start = sinf(rotateBy) * tempCap2InnerVertexEnd.x + cosf(rotateBy) * tempCap2InnerVertexEnd.y;
                const end = sinf(rotateBy) * tempCap2OuterVertexEnd.x + cosf(rotateBy) * tempCap2OuterVertexEnd.y;
                const tCross = start / (start - end);

                const intersection = lerp(cap2InnerVertexEnd, cap2OuterVertexEnd, tCross);

                if (@rem(segments, 2) == 0) {
                    // An even number of segments has 1 vertex exactly in the middle
                    const middleInnerVertex = polar(center, startAngle + angle, outerInnerRadius);

                    outlineQuad(uv, intersection, cap1OuterVertexEnd, cap1OuterVertexBeforeEnd, middleInnerVertex);
                    outlineQuad(uv, intersection, middleInnerVertex, cap2OuterVertexBeforeEnd, cap2OuterVertexEnd);
                } else {
                    // An odd number of segments has 2 vertices in the middle
                    const middleInnerVertex1 = polar(center, startAngle + angle, outerInnerRadius);
                    const middleInnerVertex2 = polar(center, endAngle - angle, outerInnerRadius);

                    outlineQuad(uv, intersection, cap1OuterVertexEnd, cap1OuterVertexBeforeEnd, middleInnerVertex1);
                    outlineQuad(uv, intersection, middleInnerVertex2, cap2OuterVertexBeforeEnd, cap2OuterVertexEnd);

                    // Triangle between the caps
                    outlineQuad(uv, intersection, intersection, middleInnerVertex1, middleInnerVertex2);
                }
            } else {
                outlineQuad(uv, cap1OuterVertexBeforeEnd, cap1InnerVertexBeforeEnd, cap1InnerVertexEnd, cap1OuterVertexEnd);
                outlineQuad(uv, cap2OuterVertexBeforeEnd, cap2OuterVertexEnd, cap2InnerVertexEnd, cap2InnerVertexBeforeEnd);
            }
        } else {
            // Cap 1
            const cap1FirstInnerVertex = polar(center, startAngle, innerInnerRadius);
            const cap1FirstOuterVertex = polar(center, startAngle, outerOuterRadius);
            outlineQuad(uv, cap1FirstInnerVertex, cap1FirstOuterVertex, caps.cap1SecondOuter, caps.cap1SecondInner);

            // Cap 2
            const cap2FirstInnerVertex = polar(center, endAngle, innerInnerRadius);
            const cap2FirstOuterVertex = polar(center, endAngle, outerOuterRadius);
            outlineQuad(uv, cap2FirstInnerVertex, caps.cap2SecondInner, caps.cap2SecondOuter, cap2FirstOuterVertex);

            if (caps.intersection) |intersection| {
                outlineQuad(uv, caps.cap1SecondInner, caps.cap1SecondInner, caps.cap1SecondOuter, intersection);
                outlineQuad(uv, caps.cap2SecondInner, intersection, caps.cap2SecondOuter, caps.cap2SecondInner);
            }
        }
    }
    rlEnd();
    // NOTE: Unlike the other textured shapes, raylib 6.2 leaves the shapes texture bound here
    // (no rlSetTexture(0)); kept as-is for identical batching behavior
}

// Lerp 't' at which a ring cap's end angle crosses the outline segment that follows
// `steps` whole steps along a `radius` arc (with the cap end rotated to 0 degrees)
fn capEndLerp(steps: c_int, stepLength: f32, capEndAngle: f32, radius: f32) f32 {
    const before = polarOrigin(@as(f32, @floatFromInt(steps)) * stepLength - capEndAngle, radius);
    const after = polarOrigin(@as(f32, @floatFromInt(steps + 1)) * stepLength - capEndAngle, radius);
    return before.y / (before.y - after.y);
}

// Second (far) vertices of the two caps of a ring outline drawn with negative thickness
//
// Cap 1, in a frame of reference where `center` is the origin and `startAngle` is 0 degrees
// (cap 2 mirrors it on `endAngle`):
//
//   I2[][][][][]O2  <- y = thick
//   []          []
//   I0----------O0  <- angle = 0 degrees, y = 0
//   []          []
//   I1          O1  <- angle = stepLength
//
// I0/O0 lie on `innerInnerRadius`/`outerOuterRadius` at `startAngle`, I1/O1 one step further,
// and I2/O2 go out perpendicular to `startAngle`. The caps can intersect in two ways: the
// I0->I2 edges crossing either the I2->O2 edges or the O0->O2 edges.
const NegativeRingCaps = struct {
    cap1SecondInner: Vector2,
    cap1SecondOuter: Vector2,
    cap2SecondInner: Vector2,
    cap2SecondOuter: Vector2,
    // Where the caps' long (I2->O2) edges cross each other, if they do
    intersection: ?Vector2,

    fn init(center: Vector2, startAngle: f32, endAngle: f32, stepLength: f32, thick: f32, innerInnerRadius: f32, outerOuterRadius: f32) NegativeRingCaps {
        const sweep = endAngle - startAngle;
        const capLongEdgeLength = outerOuterRadius - innerInnerRadius;

        // O2 is found by its lerp 't' from O1 to O0 at y = `thick`; since O0.y = 0 this
        // simplifies to `t = (start - value)/start`
        const cap1O0 = Vector2{ .x = outerOuterRadius, .y = 0.0 };
        const cap1O1 = polarOrigin(stepLength, outerOuterRadius);
        const tOuter = (cap1O1.y - thick) / cap1O1.y;
        var cap1O2 = Vector2{ .x = cap1O1.x + (cap1O0.x - cap1O1.x) * tOuter, .y = thick };
        var cap1I2 = Vector2{ .x = cap1O2.x - capLongEdgeLength, .y = thick };

        var cap2O0 = polarOrigin(sweep, outerOuterRadius);
        const cap2O1 = polarOrigin(sweep - stepLength, outerOuterRadius);
        var cap2O2 = lerp(cap2O1, cap2O0, tOuter);

        var cap2I0 = polarOrigin(sweep, innerInnerRadius);
        var cap2I2 = Vector2{ .x = cap2O2.x - cosf(DEG2RAD * sweep) * capLongEdgeLength, .y = cap2O2.y - sinf(DEG2RAD * sweep) * capLongEdgeLength };

        // The 't' of the intersection between cap 2's I2 and O2 and cap 1's long edge
        var tCapLongEdgeCross: f32 = -1.0;
        var capsIntersect = false;
        // Avoid division by zero
        if (cap2I2.y - cap2O2.y != 0.0) {
            tCapLongEdgeCross = (cap2I2.y - thick) / (cap2I2.y - cap2O2.y);
            if ((tCapLongEdgeCross >= 0.0) and (tCapLongEdgeCross <= 1.0)) capsIntersect = true;
        }

        // Rotate the frame of reference so that cap 1's I0->I2 edge is a vertical line;
        // only the 'x' coordinates are needed
        const rotateBy = -DEG2RAD * stepLength / 2.0;
        const cosres = cosf(rotateBy);
        const sinres = sinf(rotateBy);

        cap1I2.x = cap1I2.x * cosres - cap1I2.y * sinres;
        cap1O2.x = cap1O2.x * cosres - cap1O2.y * sinres;
        cap2I0.x = cap2I0.x * cosres - cap2I0.y * sinres;
        cap2I2.x = cap2I2.x * cosres - cap2I2.y * sinres;
        cap2O0.x = cap2O0.x * cosres - cap2O0.y * sinres;
        cap2O2.x = cap2O2.x * cosres - cap2O2.y * sinres;

        // The 't' of the intersection between I0 and I2 (`Lerp(I0, I2, t)`)
        var tCrossInner: f32 = -1.0;
        // Avoid division by zero
        if (cap2I0.x - cap2I2.x != 0.0) tCrossInner = (cap2I0.x - cap1I2.x) / (cap2I0.x - cap2I2.x);
        // Make sure `tCrossInner` is 0 when it should be (mitigate floating-point rounding woes)
        if (innerInnerRadius <= 0.0) tCrossInner = 0.0;

        // The 't' of the intersection between O0 and O2 (`Lerp(O0, O2, t)`)
        var tCrossOuter: f32 = -1.0;
        // Avoid division by zero
        if (cap2O0.x - cap2O2.x != 0.0) tCrossOuter = (cap2O0.x - cap1O2.x) / (cap2O0.x - cap2O2.x);

        // Recompute the vertices outside of the modified frame of reference
        const worldCap1O2 = lerp(polar(center, startAngle + stepLength, outerOuterRadius), polar(center, startAngle, outerOuterRadius), tOuter);
        const worldCap2O0 = polar(center, endAngle, outerOuterRadius);
        const worldCap2O2 = lerp(polar(center, endAngle - stepLength, outerOuterRadius), worldCap2O0, tOuter);
        const worldCap1I2 = Vector2{ .x = worldCap1O2.x - cosf(DEG2RAD * startAngle) * capLongEdgeLength, .y = worldCap1O2.y - sinf(DEG2RAD * startAngle) * capLongEdgeLength };
        const worldCap2I0 = polar(center, endAngle, innerInnerRadius);
        const worldCap2I2 = Vector2{ .x = worldCap2O2.x - cosf(DEG2RAD * endAngle) * capLongEdgeLength, .y = worldCap2O2.y - sinf(DEG2RAD * endAngle) * capLongEdgeLength };

        if (capsIntersect) {
            const inner = lerp(worldCap2I0, worldCap2I2, tCrossInner);
            return .{
                .cap1SecondInner = inner,
                .cap1SecondOuter = worldCap1O2,
                .cap2SecondInner = inner,
                .cap2SecondOuter = worldCap2O2,
                .intersection = lerp(worldCap2I2, worldCap2O2, tCapLongEdgeCross),
            };
        }
        if ((tCrossOuter >= 0.0) and (tCrossOuter <= 1.0)) {
            const outer = lerp(worldCap2O0, worldCap2O2, tCrossOuter);
            const inner = lerp(worldCap2I0, worldCap2I2, tCrossInner);
            return .{
                .cap1SecondInner = inner,
                .cap1SecondOuter = outer,
                .cap2SecondInner = inner,
                .cap2SecondOuter = outer,
                .intersection = null,
            };
        }
        return .{
            .cap1SecondInner = worldCap1I2,
            .cap1SecondOuter = worldCap1O2,
            .cap2SecondInner = worldCap2I2,
            .cap2SecondOuter = worldCap2O2,
            .intersection = null,
        };
    }
};

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
