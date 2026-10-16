//! raylib [shapes] example - penrose tile
//!
//! Zig-API translation of examples/shapes/shapes_penrose_tile.c (raylib 6.2).
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2025 David Buzatto (@davidbuzatto)

const std = @import("std");
const rl = @import("raylib");

const str_max_size = 10000;
const turtle_stack_max_size = 50;

const TurtleState = struct {
    origin: rl.Vector2 = .{ .x = 0, .y = 0 },
    angle: f32 = 0,
};

const TurtleStack = struct {
    items: [turtle_stack_max_size]TurtleState = undefined,
    len: usize = 0,

    /// Push turtle state for next step
    fn push(stack: *TurtleStack, state: TurtleState) void {
        if (stack.len < turtle_stack_max_size) {
            stack.items[stack.len] = state;
            stack.len += 1;
        } else rl.traceLog(.warning, "TURTLE STACK OVERFLOW!", .{});
    }

    /// Pop turtle state step
    fn pop(stack: *TurtleStack) TurtleState {
        if (stack.len == 0) {
            rl.traceLog(.warning, "TURTLE STACK UNDERFLOW!", .{});
            return .{};
        }
        stack.len -= 1;
        return stack.items[stack.len];
    }
};

/// A production string, truncated (like the C `strncat`) to `str_max_size - 1` characters.
const Production = struct {
    buffer: [str_max_size - 1]u8 = undefined,
    len: usize = 0,

    fn init(text: []const u8) Production {
        var production: Production = .{};
        production.append(text);
        return production;
    }

    fn append(production: *Production, text: []const u8) void {
        const n = @min(text.len, production.buffer.len - production.len);
        @memcpy(production.buffer[production.len..][0..n], text[0..n]);
        production.len += n;
    }

    fn slice(production: *const Production) []const u8 {
        return production.buffer[0..production.len];
    }
};

const PenroseLSystem = struct {
    steps: usize = 0,
    production: Production,
    draw_length: f32,
    theta: f32 = 36.0, // Degrees

    const rule_w = "YF++ZF4-XF[-YF4-WF]++";
    const rule_x = "+YF--ZF[3-WF--XF]+";
    const rule_y = "-WF++XF[+++YF++ZF]-";
    const rule_z = "--YF++++WF[+ZF++++XF]--XF";

    /// Create a new penrose tile structure, built up to `generations`
    fn init(draw_length: f32, generations: u32) PenroseLSystem {
        var ls: PenroseLSystem = .{
            .production = .init("[X]++[X]++[X]++[X]++[X]"),
            .draw_length = draw_length,
        };
        for (0..generations) |_| ls.buildProductionStep();
        return ls;
    }

    /// Build next penrose step
    fn buildProductionStep(ls: *PenroseLSystem) void {
        var new_production: Production = .{};

        for (ls.production.slice()) |step| {
            switch (step) {
                'W' => new_production.append(rule_w),
                'X' => new_production.append(rule_x),
                'Y' => new_production.append(rule_y),
                'Z' => new_production.append(rule_z),
                'F' => {},
                else => new_production.append(&.{step}),
            }
        }

        ls.draw_length *= 0.5;
        ls.production = new_production;
    }

    /// Draw penrose tile lines
    fn draw(ls: *PenroseLSystem) void {
        const screen_center: rl.Vector2 = .{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
            .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
        };

        var turtle: TurtleState = .{ .angle = -90.0 };
        var stack: TurtleStack = .{};

        var repeats: u32 = 1;
        ls.steps = @min(ls.steps + 12, ls.production.len);

        for (ls.production.slice()[0..ls.steps]) |step| {
            switch (step) {
                'F' => {
                    for (0..repeats) |_| {
                        const start_pos_world = turtle.origin;
                        const rad_angle = rl.deg2rad * turtle.angle;
                        turtle.origin.x += ls.draw_length * @cos(rad_angle);
                        turtle.origin.y += ls.draw_length * @sin(rad_angle);
                        const start_pos_screen: rl.Vector2 = .{ .x = start_pos_world.x + screen_center.x, .y = start_pos_world.y + screen_center.y };
                        const end_pos_screen: rl.Vector2 = .{ .x = turtle.origin.x + screen_center.x, .y = turtle.origin.y + screen_center.y };

                        rl.drawLineEx(start_pos_screen, end_pos_screen, 2, rl.fade(.black, 0.2));
                    }
                    repeats = 1;
                },
                '+' => {
                    for (0..repeats) |_| turtle.angle += ls.theta;
                    repeats = 1;
                },
                '-' => {
                    for (0..repeats) |_| turtle.angle += -ls.theta;
                    repeats = 1;
                },
                '[' => stack.push(turtle),
                ']' => turtle = stack.pop(),
                '0'...'9' => repeats = step - '0',
                else => {},
            }
        }
    }
};

pub fn main() void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [shapes] example - penrose tile");
    defer rl.closeWindow(); // Close window and OpenGL context

    const draw_length: f32 = 460.0;
    const min_generations = 0;
    const max_generations = 4;
    var generations: u32 = 0;

    // Initialize new penrose tile
    var ls: PenroseLSystem = .init(draw_length * (@as(f32, @floatFromInt(generations)) / max_generations), generations);

    rl.setTargetFPS(120); // Set our game to run at 120 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        var rebuild = false;
        if (rl.isKeyPressed(.up)) {
            if (generations < max_generations) {
                generations += 1;
                rebuild = true;
            }
        } else if (rl.isKeyPressed(.down)) {
            if (generations > min_generations) {
                generations -= 1;
                if (generations > 0) rebuild = true;
            }
        }

        if (rebuild) {
            ls = .init(draw_length * (@as(f32, @floatFromInt(generations)) / max_generations), generations);
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (generations > 0) ls.draw();

        rl.drawText("penrose l-system", 10, 10, 20, .dark_gray);
        rl.drawText("press up or down to change generations", 10, 30, 20, .dark_gray);
        rl.drawText(rl.textFormat("generations: {d}", .{generations}), 10, 50, 20, .dark_gray);
    }
}
