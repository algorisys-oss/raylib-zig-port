//! Slingshot game logic: entities, physics, levels, rendering.
//!
//! Behavioral port of the C# reference (csharp-raylib-angrybirds). Entities
//! are bags of optional components (body, health); behavior lives in the
//! physics step and the game-state update, not on the entities. Dynamic
//! entities are circles (bird, pigs), blocks are static boxes, which keeps
//! the collision math to two cases.

const std = @import("std");
const rl = @import("raylib.zig");

pub const screen_width = 1280;
pub const screen_height = 720;

// Physics tuning.
const gravity = 1150.0;
pub const ground_y = 660.0;
const rest_speed = 14.0; // below this speed a body counts as settled
const damage_speed = 140.0; // impacts slower than this do no harm
const damage_scale = 0.06; // hp lost per px/s of impact above the threshold

// Slingshot tuning.
pub const anchor: rl.Vector2 = .{ .x = 230, .y = 470 };
pub const max_stretch = 135.0;
const power = 9.5;
const grab_radius = 220.0;

const Kind = enum { bird, pig, block };

const Shape = union(enum) {
    circle: f32, // radius
    box: rl.Vector2, // half-extents
};

const Body = struct {
    velocity: rl.Vector2 = .zero,
    mass: f32,
    restitution: f32, // bounciness, 0..1
    friction: f32, // tangential damping on ground contact
    resting: bool = false, // true once it has settled
};

const Health = struct {
    value: f32,
    max: f32,

    fn init(value: f32) Health {
        return .{ .value = value, .max = value };
    }

    fn fraction(h: Health) f32 {
        return if (h.max <= 0) 0 else h.value / h.max;
    }
};

const Entity = struct {
    kind: Kind,
    pos: rl.Vector2,
    shape: Shape,
    body: ?Body = null, // null => static (never moves)
    health: ?Health = null, // null => indestructible
    color: rl.Color,
    dead: bool = false, // out of play; skipped everywhere, culled on level load
    scored: bool = false, // score already awarded for this death

    fn isStatic(e: Entity) bool {
        return e.body == null;
    }

    fn makeBird(p: rl.Vector2) Entity {
        return .{
            .kind = .bird,
            .pos = p,
            .shape = .{ .circle = 16 },
            .body = .{ .mass = 1.5, .restitution = 0.45, .friction = 0.72 },
            .color = rl.red,
        };
    }

    fn makePig(p: rl.Vector2) Entity {
        return .{
            .kind = .pig,
            .pos = p,
            .shape = .{ .circle = 20 },
            .body = .{ .mass = 1, .restitution = 0.35, .friction = 0.85 },
            .health = .init(45),
            .color = rl.lime,
        };
    }

    fn makeBlock(p: rl.Vector2, w: f32, h: f32) Entity {
        return .{
            .kind = .block,
            .pos = p,
            .shape = .{ .box = .{ .x = w / 2, .y = h / 2 } },
            .health = .init(70),
            .color = rl.brown,
        };
    }
};

/// A level is pure data: how many birds, where the pigs sit, and which
/// blocks form the structures.
const Level = struct {
    birds: u32,
    pigs: []const rl.Vector2,
    blocks: []const Block,

    const Block = struct { pos: rl.Vector2, w: f32, h: f32 };
};

const levels = [_]Level{
    // Level 1 - one pig behind a small wall.
    .{
        .birds = 3,
        .pigs = &.{.{ .x = 980, .y = 620 }},
        .blocks = &.{
            .{ .pos = .{ .x = 900, .y = 600 }, .w = 24, .h = 120 },
            .{ .pos = .{ .x = 900, .y = 530 }, .w = 120, .h = 24 },
        },
    },
    // Level 2 - two pigs, a little tower.
    .{
        .birds = 4,
        .pigs = &.{ .{ .x = 860, .y = 620 }, .{ .x = 1040, .y = 560 } },
        .blocks = &.{
            .{ .pos = .{ .x = 1040, .y = 620 }, .w = 140, .h = 24 },
            .{ .pos = .{ .x = 980, .y = 590 }, .w = 24, .h = 60 },
            .{ .pos = .{ .x = 1100, .y = 590 }, .w = 24, .h = 60 },
            .{ .pos = .{ .x = 820, .y = 600 }, .w = 24, .h = 120 },
        },
    },
    // Level 3 - a little house: one pig out front, one inside, one on the roof.
    .{
        .birds = 5,
        .pigs = &.{
            .{ .x = 820, .y = 640 }, // out front, on the ground
            .{ .x = 970, .y = 640 }, // inside the house, on the ground
            .{ .x = 970, .y = 496 }, // resting on the roof
        },
        .blocks = &.{
            .{ .pos = .{ .x = 900, .y = 600 }, .w = 24, .h = 120 }, // left wall
            .{ .pos = .{ .x = 1040, .y = 600 }, .w = 24, .h = 120 }, // right wall
            .{ .pos = .{ .x = 970, .y = 528 }, .w = 164, .h = 24 }, // roof
        },
    },
};

/// One frame of player intent, decoupled from raylib so the self-test can
/// drive the exact same update path with scripted input.
pub const Input = struct {
    mouse: rl.Vector2 = .zero,
    pressed: bool = false, // left mouse button went down this frame
    released: bool = false, // left mouse button went up this frame
    restart: bool = false, // R
    advance: bool = false, // SPACE or N

    /// Sample this frame's real input from raylib.
    pub fn poll() Input {
        return .{
            .mouse = rl.GetMousePosition(),
            .pressed = rl.IsMouseButtonPressed(.left),
            .released = rl.IsMouseButtonReleased(.left),
            .restart = rl.IsKeyPressed(.r),
            .advance = rl.IsKeyPressed(.space) or rl.IsKeyPressed(.n),
        };
    }
};

pub const State = enum { aiming, flying, level_clear, game_over };

pub const Game = struct {
    gpa: std.mem.Allocator,
    entities: std.ArrayList(Entity) = .empty,
    bird: ?usize = null, // index of the live bird; entities are stable per level
    dragging: bool = false,
    level_index: usize = 0,
    birds_left: u32 = 0,
    score: u32 = 0,
    settle_timer: f32 = 0,
    state: State = .aiming,

    pub fn init(gpa: std.mem.Allocator) !Game {
        var game: Game = .{ .gpa = gpa };
        try game.loadLevel(0);
        return game;
    }

    pub fn deinit(game: *Game) void {
        game.entities.deinit(game.gpa);
        game.* = undefined;
    }

    // --- Level / turn flow ---------------------------------------------

    fn loadLevel(game: *Game, index: usize) !void {
        game.level_index = index % levels.len;
        const level = levels[game.level_index];

        game.entities.clearRetainingCapacity();
        for (level.pigs) |p| try game.entities.append(game.gpa, .makePig(p));
        for (level.blocks) |b| try game.entities.append(game.gpa, .makeBlock(b.pos, b.w, b.h));

        game.birds_left = level.birds;
        game.bird = null;
        game.dragging = false;
        game.state = .aiming;
        try game.spawnBird();
    }

    fn spawnBird(game: *Game) !void {
        if (game.birds_left == 0) {
            game.bird = null;
            return;
        }
        game.birds_left -= 1;
        try game.entities.append(game.gpa, .makeBird(anchor));
        game.bird = game.entities.items.len - 1;
        game.state = .aiming;
        game.settle_timer = 0;
    }

    pub fn pigsLeft(game: *const Game) usize {
        var count: usize = 0;
        for (game.entities.items) |e| {
            if (e.kind == .pig and !e.dead) count += 1;
        }
        return count;
    }

    fn endTurn(game: *Game) !void {
        if (game.pigsLeft() == 0) {
            game.state = .level_clear;
            return;
        }
        if (game.birds_left > 0) try game.spawnBird() else game.state = .game_over;
    }

    // --- Update --------------------------------------------------------

    pub fn update(game: *Game, input: Input, dt: f32) !void {
        switch (game.state) {
            .aiming => game.updateAiming(input),
            .flying => try game.updateFlying(dt),
            .level_clear => if (input.advance) try game.loadLevel(game.level_index + 1),
            .game_over => if (input.restart or input.advance) try game.loadLevel(game.level_index),
        }

        // Restart the current level at any time.
        if (input.restart and game.state != .game_over) try game.loadLevel(game.level_index);
    }

    fn updateAiming(game: *Game, input: Input) void {
        const bird = &game.entities.items[game.bird orelse return];

        if (input.pressed and input.mouse.distance(anchor) < grab_radius)
            game.dragging = true;

        if (!game.dragging) return;

        var pull = input.mouse.sub(anchor);
        if (pull.length() > max_stretch)
            pull = pull.scale(max_stretch / pull.length());
        bird.pos = anchor.add(pull);

        if (input.released) {
            bird.body.?.velocity = anchor.sub(bird.pos).scale(power);
            game.dragging = false;
            game.state = .flying;
            game.settle_timer = 0;
        }
    }

    fn updateFlying(game: *Game, dt: f32) !void {
        physicsStep(game.entities.items, dt);
        game.cullOffWorld();
        game.awardScores(); // score deaths as they happen

        const bird_index = game.bird orelse return game.endTurn();
        const bird = &game.entities.items[bird_index];

        const offscreen = bird.pos.x > screen_width + 60 or bird.pos.x < -60 or
            bird.pos.y > screen_height + 60;
        game.settle_timer = if (bird.body.?.resting) game.settle_timer + dt else 0;

        if (offscreen or game.settle_timer > 0.8) {
            // Retire the bird: out of play, and never worth points.
            bird.dead = true;
            bird.scored = true;
            game.bird = null;
            try game.endTurn();
        }
    }

    /// Anything dynamic that leaves the world is gone for good. A pig knocked
    /// off the screen counts as defeated, so the level can still be cleared.
    fn cullOffWorld(game: *Game) void {
        for (game.entities.items, 0..) |*e, i| {
            if (e.isStatic() or e.dead or i == game.bird) continue;
            if (e.pos.y > screen_height + 40 or e.pos.x < -40 or e.pos.x > screen_width + 40)
                e.dead = true;
        }
    }

    fn awardScores(game: *Game) void {
        for (game.entities.items) |*e| {
            if (!e.dead or e.scored) continue;
            e.scored = true;
            game.score += if (e.kind == .pig) 1000 else 200;
        }
    }

    // --- Draw ----------------------------------------------------------

    pub fn draw(game: *const Game) void {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.DrawRectangleGradientV(0, 0, screen_width, screen_height, rl.sky_blue, .{ .r = 225, .g = 245, .b = 255, .a = 255 });

        // Ground.
        const gy: c_int = ground_y;
        rl.DrawRectangle(0, gy, screen_width, screen_height - gy, .{ .r = 110, .g = 170, .b = 90, .a = 255 });
        rl.DrawRectangle(0, gy, screen_width, 6, .{ .r = 80, .g = 140, .b = 65, .a = 255 });

        game.drawSlingshot();
        for (game.entities.items) |e| drawEntity(e);
        if (game.state == .aiming and game.dragging) game.drawTrajectory();

        game.drawHud();
    }

    fn drawSlingshot(game: *const Game) void {
        const base: rl.Vector2 = .{ .x = anchor.x, .y = ground_y };
        rl.DrawLineEx(base, anchor, 12, .{ .r = 120, .g = 75, .b = 40, .a = 255 });

        if (game.state != .aiming) return;
        const bird = game.entities.items[game.bird orelse return];
        const band: rl.Color = .{ .r = 60, .g = 40, .b = 25, .a = 255 };
        rl.DrawLineEx(.{ .x = anchor.x - 12, .y = anchor.y }, bird.pos, 6, band);
        rl.DrawLineEx(.{ .x = anchor.x + 12, .y = anchor.y }, bird.pos, 6, band);
    }

    fn drawTrajectory(game: *const Game) void {
        const bird = game.entities.items[game.bird orelse return];
        var pos = bird.pos;
        var vel = anchor.sub(bird.pos).scale(power);
        const dt = 1.0 / 60.0;
        for (0..40) |i| {
            vel.y += gravity * dt;
            pos = pos.add(vel.scale(dt));
            if (i % 2 == 0)
                rl.DrawCircleV(pos, 3, .{ .r = 255, .g = 255, .b = 255, .a = 180 });
        }
    }

    fn drawHud(game: *const Game) void {
        const on_sling: u32 = if (game.bird != null) 1 else 0;
        drawTextFmt(20, 20, 28, rl.black, "Level {d}", .{game.level_index + 1});
        drawTextFmt(20, 54, 24, rl.dark_gray, "Score: {d}", .{game.score});
        drawTextFmt(20, 82, 24, rl.dark_gray, "Birds left: {d}", .{game.birds_left + on_sling});
        drawTextFmt(20, 110, 24, rl.dark_green, "Pigs left: {d}", .{game.pigsLeft()});

        switch (game.state) {
            .aiming => rl.DrawText("Drag the bird back and release to fire", 20, screen_height - 36, 22, rl.dark_gray),
            .level_clear => banner("LEVEL CLEAR!", "Press SPACE for the next level", rl.dark_green),
            .game_over => banner("OUT OF BIRDS", "Press R to retry this level", rl.maroon),
            .flying => {},
        }
    }
};

// --- Physics ------------------------------------------------------------

fn physicsStep(entities: []Entity, dt: f32) void {
    for (entities) |*e| {
        if (e.dead) continue;
        if (e.body) |*b| {
            b.velocity.y += gravity * dt;
            e.pos = e.pos.add(b.velocity.scale(dt));
            resolveGround(e, b);
        }
    }

    resolveCollisions(entities);

    for (entities) |*e| {
        if (e.body) |*b| b.resting = b.velocity.length() < rest_speed;
    }
}

fn resolveGround(e: *Entity, b: *Body) void {
    const r = e.shape.circle; // dynamic entities are always circles
    if (e.pos.y + r <= ground_y) return;

    e.pos.y = ground_y - r;
    if (b.velocity.y > 0)
        b.velocity.y = -b.velocity.y * b.restitution;
    b.velocity.x *= b.friction;
    if (@abs(b.velocity.y) < rest_speed) b.velocity.y = 0;
}

fn resolveCollisions(entities: []Entity) void {
    for (entities, 0..) |*a, i| {
        if (a.dead) continue;
        for (entities[i + 1 ..]) |*b| {
            if (b.dead) continue;
            if (a.isStatic() and b.isStatic()) continue;

            // Normalize the pair so circle-vs-box always passes (circle, box).
            switch (a.shape) {
                .circle => switch (b.shape) {
                    .circle => circleVsCircle(a, b),
                    .box => circleVsBox(a, b),
                },
                .box => circleVsBox(b, a),
            }
        }
    }
}

fn circleVsCircle(a: *Entity, b: *Entity) void {
    var d = b.pos.sub(a.pos);
    var dist = d.length();
    const r_sum = a.shape.circle + b.shape.circle;
    if (dist >= r_sum) return;
    if (dist < 0.0001) {
        d = .{ .x = 0, .y = -1 };
        dist = 0.0001;
    }

    const n = d.scale(1 / dist);
    const pen = r_sum - dist;

    const inv_a: f32 = if (a.body) |body| 1 / body.mass else 0;
    const inv_b: f32 = if (b.body) |body| 1 / body.mass else 0;
    const inv_sum = inv_a + inv_b;
    if (inv_sum == 0) return;

    // Positional correction, weighted by inverse mass.
    a.pos = a.pos.sub(n.scale(pen * inv_a / inv_sum));
    b.pos = b.pos.add(n.scale(pen * inv_b / inv_sum));

    const va = if (a.body) |body| body.velocity else rl.Vector2.zero;
    const vb = if (b.body) |body| body.velocity else rl.Vector2.zero;
    const vn = vb.sub(va).dot(n);
    if (vn > 0) return; // already separating

    const restitution = 0.3;
    const impulse = n.scale(-(1 + restitution) * vn / inv_sum);
    if (a.body) |*body| body.velocity = body.velocity.sub(impulse.scale(inv_a));
    if (b.body) |*body| body.velocity = body.velocity.add(impulse.scale(inv_b));

    const impact = @abs(vn);
    applyImpact(a, impact);
    applyImpact(b, impact);
}

fn circleVsBox(circle: *Entity, box: *Entity) void {
    const half = box.shape.box;
    const d = circle.pos.sub(box.pos);
    const closest = box.pos.add(.{
        .x = std.math.clamp(d.x, -half.x, half.x),
        .y = std.math.clamp(d.y, -half.y, half.y),
    });
    var diff = circle.pos.sub(closest);
    var dist = diff.length();
    const r = circle.shape.circle;
    if (dist >= r) return;
    if (dist < 0.0001) {
        diff = .{ .x = 0, .y = -1 };
        dist = 0.0001;
    }

    const n = diff.scale(1 / dist);
    circle.pos = circle.pos.add(n.scale(r - dist));

    const body = &circle.body.?;
    const vn = body.velocity.dot(n);
    if (vn < 0) {
        const impact = -vn;
        body.velocity = body.velocity.sub(n.scale((1 + body.restitution) * vn));
        applyImpact(box, impact);
        applyImpact(circle, impact);
    }
}

fn applyImpact(e: *Entity, impact_speed: f32) void {
    const health = if (e.health) |*h| h else return;
    if (impact_speed < damage_speed) return;
    health.value -= (impact_speed - damage_speed) * damage_scale;
    if (health.value <= 0) e.dead = true;
}

// --- Drawing helpers ------------------------------------------------------

fn drawEntity(e: Entity) void {
    if (e.dead) return;

    switch (e.shape) {
        .circle => |r| {
            rl.DrawCircleV(e.pos, r, e.color);
            rl.DrawCircleLinesV(e.pos, r, rl.black);
            if (e.kind == .pig) { // little eyes
                rl.DrawCircleV(e.pos.add(.{ .x = -6, .y = -5 }), 3, rl.black);
                rl.DrawCircleV(e.pos.add(.{ .x = 6, .y = -5 }), 3, rl.black);
            }
        },
        .box => |half| {
            const rect: rl.Rectangle = .{
                .x = e.pos.x - half.x,
                .y = e.pos.y - half.y,
                .width = half.x * 2,
                .height = half.y * 2,
            };
            // Tint darker as the block takes damage.
            var c = e.color;
            if (e.health) |h| {
                const f = h.fraction();
                c = .{
                    .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * f),
                    .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * f),
                    .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * f),
                    .a = 255,
                };
            }
            rl.DrawRectangleRec(rect, c);
            rl.DrawRectangleLinesEx(rect, 2, rl.black);
        },
    }
}

fn banner(title: [*:0]const u8, sub: [*:0]const u8, color: rl.Color) void {
    rl.DrawRectangle(0, screen_height / 2 - 70, screen_width, 140, .{ .r = 0, .g = 0, .b = 0, .a = 150 });
    const tw = rl.MeasureText(title, 56);
    rl.DrawText(title, screen_width / 2 - @divTrunc(tw, 2), screen_height / 2 - 50, 56, color);
    const sw = rl.MeasureText(sub, 26);
    rl.DrawText(sub, screen_width / 2 - @divTrunc(sw, 2), screen_height / 2 + 18, 26, rl.ray_white);
}

fn drawTextFmt(x: c_int, y: c_int, size: c_int, color: rl.Color, comptime fmt: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    // The HUD strings are all short; 128 bytes cannot overflow.
    const text = std.fmt.bufPrintSentinel(&buf, fmt, args, 0) catch unreachable;
    rl.DrawText(text, x, y, size, color);
}
