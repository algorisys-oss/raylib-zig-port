//! raylib [text] example - unicode emojis
//!
//! Zig-API translation of examples/text/text_unicode_emojis.c (raylib 6.2).
//! Example contributed by Vlad Adrian (@demizdor) and reviewed by Ramon Santamaria (@raysan5)
//! Example licensed under an unmodified zlib/libpng license.
//! Copyright (c) 2019-2025 Vlad Adrian (@demizdor) and Ramon Santamaria (@raysan5)

const std = @import("std");
const rl = @import("raylib");

const emoji_per_width = 8;
const emoji_per_height = 4;

/// A random emoji shown in the background grid
const Emoji = struct {
    index: usize, // Index inside `emoji_codepoints`
    message: usize, // Message index
    color: rl.Color, // Emoji color
};

const Message = struct {
    text: [:0]const u8,
    language: [:0]const u8,
};

// 180 emoji codepoints, UTF-8 encoded
const emoji_codepoints = [_][:0]const u8{
    "🌀",
    "😀",
    "😂",
    "🤣",
    "😃",
    "😆",
    "😉",
    "😋",
    "😎",
    "😍",
    "😘",
    "😗",
    "😙",
    "😚",
    "🙂",
    "🤗",
    "🤩",
    "🤔",
    "🤨",
    "😐",
    "😑",
    "😶",
    "🙄",
    "😏",
    "😣",
    "😥",
    "😮",
    "🤐",
    "😯",
    "😪",
    "😫",
    "😴",
    "😌",
    "😛",
    "😝",
    "🤤",
    "😒",
    "😕",
    "🙃",
    "🤑",
    "😲",
    "🙁",
    "😖",
    "😞",
    "😟",
    "😤",
    "😢",
    "😭",
    "😦",
    "😩",
    "🤯",
    "😬",
    "😰",
    "😱",
    "😳",
    "🤪",
    "😵",
    "😡",
    "😠",
    "🤬",
    "😷",
    "🤒",
    "🤕",
    "🤢",
    "🤮",
    "🤧",
    "😇",
    "🤠",
    "🤫",
    "🤭",
    "🧐",
    "🤓",
    "😈",
    "👿",
    "👹",
    "👺",
    "💀",
    "👻",
    "👽",
    "👾",
    "🤖",
    "💩",
    "😺",
    "😸",
    "😹",
    "😻",
    "😽",
    "🙀",
    "😿",
    "🌾",
    "🌿",
    "🍀",
    "🍃",
    "🍇",
    "🍓",
    "🥝",
    "🍅",
    "🥥",
    "🥑",
    "🍆",
    "🥔",
    "🥕",
    "🌽",
    "🌶",
    "🥒",
    "🥦",
    "🍄",
    "🥜",
    "🌰",
    "🍞",
    "🥐",
    "🥖",
    "🥨",
    "🥞",
    "🧀",
    "🍖",
    "🍗",
    "🥩",
    "🥓",
    "🍔",
    "🍟",
    "🍕",
    "🌭",
    "🥪",
    "🌮",
    "🌯",
    "🥙",
    "🥚",
    "🍳",
    "🥘",
    "🍲",
    "🥣",
    "🥗",
    "🍿",
    "🥫",
    "🍱",
    "🍘",
    "🍝",
    "🍠",
    "🍢",
    "🍥",
    "🍡",
    "🥟",
    "🥡",
    "🍦",
    "🍪",
    "🎂",
    "🍰",
    "🥧",
    "🍫",
    "🍯",
    "🍼",
    "🥛",
    "🍵",
    "🍶",
    "🍾",
    "🍷",
    "🍻",
    "🥂",
    "🥃",
    "🥤",
    "🥢",
    "👁",
    "👅",
    "👄",
    "💋",
    "💘",
    "💓",
    "💗",
    "💙",
    "💛",
    "🧡",
    "💜",
    "🖤",
    "💝",
    "💟",
    "💌",
    "💤",
    "💢",
    "💣",
};

const messages = [_]Message{ // Array containing all of the emojis messages
    .{ .text = "Falsches Üben von Xylophonmusik quält jeden größeren Zwerg", .language = "German" },
    .{ .text = "Beiß nicht in die Hand, die dich füttert.", .language = "German" },
    .{ .text = "Außerordentliche Übel erfordern außerordentliche Mittel.", .language = "German" },
    .{ .text = "Կրնամ ապակի ուտել և ինծի անհանգիստ չըներ", .language = "Armenian" },
    .{ .text = "Երբ որ կացինը եկաւ անտառ, ծառերը ասացին... «Կոտը մերոնցից է:»", .language = "Armenian" },
    .{ .text = "Գառը՝ գարնան, ձիւնը՝ ձմռան", .language = "Armenian" },
    .{ .text = "Jeżu klątw, spłódź Finom część gry hańb!", .language = "Polish" },
    .{ .text = "Dobrymi chęciami jest piekło wybrukowane.", .language = "Polish" },
    .{ .text = "Îți mulțumesc că ai ales raylib.\nȘi sper să ai o zi bună!", .language = "Romanian" },
    .{ .text = "Эх, чужак, общий съём цен шляп (юфть) вдрызг!", .language = "Russian" },
    .{ .text = "Я люблю raylib!", .language = "Russian" },
    .{ .text = "Молчи, скрывайся и таи\nИ чувства и мечты свои –\nПускай в душевной глубине\nИ всходят и зайдут оне\nКак звезды ясные в ночи-\nЛюбуйся ими – и молчи.", .language = "Russian" },
    .{ .text = "Voix ambiguë d’un cœur qui au zéphyr préfère les jattes de kiwi", .language = "French" },
    .{ .text = "Benjamín pidió una bebida de kiwi y fresa; Noé, sin vergüenza, la más exquisita champaña del menú.", .language = "Spanish" },
    .{ .text = "Ταχίστη αλώπηξ βαφής ψημένη γη, δρασκελίζει υπέρ νωθρού κυνός", .language = "Greek" },
    .{ .text = "Η καλύτερη άμυνα είναι η επίθεση.", .language = "Greek" },
    .{ .text = "Χρόνια και ζαμάνια!", .language = "Greek" },
    .{ .text = "Πώς τα πας σήμερα;", .language = "Greek" },
    .{ .text = "我能吞下玻璃而不伤身体。", .language = "Chinese" },
    .{ .text = "你吃了吗？", .language = "Chinese" },
    .{ .text = "不作不死。", .language = "Chinese" },
    .{ .text = "最近好吗？", .language = "Chinese" },
    .{ .text = "塞翁失马，焉知非福。", .language = "Chinese" },
    .{ .text = "千军易得, 一将难求", .language = "Chinese" },
    .{ .text = "万事开头难。", .language = "Chinese" },
    .{ .text = "风无常顺，兵无常胜。", .language = "Chinese" },
    .{ .text = "活到老，学到老。", .language = "Chinese" },
    .{ .text = "一言既出，驷马难追。", .language = "Chinese" },
    .{ .text = "路遥知马力，日久见人心", .language = "Chinese" },
    .{ .text = "有理走遍天下，无理寸步难行。", .language = "Chinese" },
    .{ .text = "猿も木から落ちる", .language = "Japanese" },
    .{ .text = "亀の甲より年の功", .language = "Japanese" },
    .{ .text = "うらやまし  思ひ切る時  猫の恋", .language = "Japanese" },
    .{ .text = "虎穴に入らずんば虎子を得ず。", .language = "Japanese" },
    .{ .text = "二兎を追う者は一兎をも得ず。", .language = "Japanese" },
    .{ .text = "馬鹿は死ななきゃ治らない。", .language = "Japanese" },
    .{ .text = "枯野路に　影かさなりて　わかれけり", .language = "Japanese" },
    .{ .text = "繰り返し麦の畝縫ふ胡蝶哉", .language = "Japanese" },
    .{ .text = "아득한 바다 위에 갈매기 두엇 날아 돈다.\n너훌너훌 시를 쓴다. 모르는 나라 글자다.\n널따란 하늘 복판에 나도 같이 시를 쓴다.", .language = "Korean" },
    .{ .text = "제 눈에 안경이다", .language = "Korean" },
    .{ .text = "꿩 먹고 알 먹는다", .language = "Korean" },
    .{ .text = "로마는 하루아침에 이루어진 것이 아니다", .language = "Korean" },
    .{ .text = "고생 끝에 낙이 온다", .language = "Korean" },
    .{ .text = "개천에서 용 난다", .language = "Korean" },
    .{ .text = "안녕하세요?", .language = "Korean" },
    .{ .text = "만나서 반갑습니다", .language = "Korean" },
    .{ .text = "한국말 하실 줄 아세요?", .language = "Korean" },
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.setConfigFlags(.{ .msaa_4x_hint = true, .vsync_hint = true });
    rl.initWindow(screen_width, screen_height, "raylib [text] example - unicode emojis");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Load the font resources
    // NOTE: fontAsian is for asian languages,
    // fontEmoji is the emojis and fontDefault is used for everything else
    const font_default = try rl.loadFont("resources/dejavu.fnt"); // Requires "resources/dejavu.png"
    defer rl.unloadFont(font_default); // Unload font resource
    const font_asian = try rl.loadFont("resources/noto_cjk.fnt"); // Requires "resources/noto_cjk.png"
    defer rl.unloadFont(font_asian); // Unload font resource
    const font_emoji = try rl.loadFont("resources/symbola.fnt"); // Requires "resources/symbola.png"
    defer rl.unloadFont(font_emoji); // Unload font resource
    const emoji_size: f32 = @floatFromInt(font_emoji.baseSize);

    var hovered: ?usize = null;
    var selected: ?usize = null;
    var hovered_pos: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };
    var selected_pos: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };

    // Set a random set of emojis when starting up
    var emojis: [emoji_per_width * emoji_per_height]Emoji = undefined;
    randomizeEmoji(&emojis);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        // Add a new set of emojis when SPACE is pressed
        if (rl.isKeyPressed(.space)) {
            randomizeEmoji(&emojis);
            hovered = null;
            selected = null;
        }

        // Set the selected emoji
        if (rl.isMouseButtonPressed(.left) and hovered != null and hovered != selected) {
            selected = hovered;
            selected_pos = hovered_pos;
        }

        const mouse = rl.getMousePosition();
        var position: rl.Vector2 = .{ .x = 28.8, .y = 10.0 };
        hovered = null;

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        // Draw random emojis in the background
        for (emojis, 0..) |emoji, i| {
            const txt = emoji_codepoints[emoji.index];
            const emoji_rect: rl.Rectangle = .{ .x = position.x, .y = position.y, .width = emoji_size, .height = emoji_size };

            if (!rl.checkCollisionPointRec(mouse, emoji_rect)) {
                rl.drawTextEx(font_emoji, txt, position, emoji_size, 1.0, if (selected == i) emoji.color else rl.fade(.light_gray, 0.4));
            } else {
                rl.drawTextEx(font_emoji, txt, position, emoji_size, 1.0, emoji.color);
                hovered = i;
                hovered_pos = position;
            }

            if (i != 0 and i % emoji_per_width == 0) {
                position.y += emoji_size + 24.25;
                position.x = 28.8;
            } else position.x += emoji_size + 28.8;
        }

        // Draw the message when a emoji is selected
        if (selected) |selected_index| {
            const emoji = emojis[selected_index];
            const message = messages[emoji.message];
            const horizontal_padding = 20;
            const vertical_padding = 30;

            // Set correct font for asian languages
            const is_asian = rl.textIsEqual(message.language, "Chinese") or
                rl.textIsEqual(message.language, "Korean") or
                rl.textIsEqual(message.language, "Japanese");
            const font = if (is_asian) font_asian else font_default;
            const font_size: f32 = @floatFromInt(font.baseSize);

            // Calculate size for the message box (approximate the height and width)
            var sz = rl.measureTextEx(font, message.text, font_size, 1.0);
            if (sz.x > 300) {
                sz.y *= sz.x / 300;
                sz.x = 300;
            } else if (sz.x < 160) sz.x = 160;

            var msg_rect: rl.Rectangle = .{ .x = selected_pos.x - 38.8, .y = selected_pos.y, .width = 2 * horizontal_padding + sz.x, .height = 2 * vertical_padding + sz.y };
            msg_rect.y -= msg_rect.height;

            // Coordinates for the chat bubble triangle
            var a: rl.Vector2 = .{ .x = selected_pos.x, .y = msg_rect.y + msg_rect.height };
            var b: rl.Vector2 = .{ .x = a.x + 8, .y = a.y + 10 };
            var c: rl.Vector2 = .{ .x = a.x + 10, .y = a.y };

            // Don't go outside the screen
            if (msg_rect.x < 10) msg_rect.x += 28;
            if (msg_rect.y < 10) {
                msg_rect.y = selected_pos.y + 84;
                a.y = msg_rect.y;
                c.y = a.y;
                b.y = a.y - 10;

                // Swap values so we can actually render the triangle :(
                std.mem.swap(rl.Vector2, &a, &b);
            }

            if (msg_rect.x + msg_rect.width > screen_width) msg_rect.x -= (msg_rect.x + msg_rect.width) - screen_width + 10;

            // Draw chat bubble
            rl.drawRectangleRec(msg_rect, emoji.color);
            rl.drawTriangle(a, b, c, emoji.color);

            // Draw the main text message
            const text_rect: rl.Rectangle = .{
                .x = msg_rect.x + @as(f32, horizontal_padding) / 2,
                .y = msg_rect.y + @as(f32, vertical_padding) / 2,
                .width = msg_rect.width - horizontal_padding,
                .height = msg_rect.height,
            };
            drawTextBoxed(font, message.text, text_rect, font_size, 1.0, true, .white);

            // Draw the info text below the main message
            const size = message.text.len;
            const length = rl.getCodepointCount(message.text);
            const info = rl.textFormat("{s} {d} characters {d} bytes", .{ message.language, length, size });
            sz = rl.measureTextEx(rl.getFontDefault(), info, 10, 1.0);

            rl.drawText(info, @intFromFloat(text_rect.x + text_rect.width - sz.x), @intFromFloat(msg_rect.y + msg_rect.height - sz.y - 2), 10, .ray_white);
        }

        // Draw the info text
        rl.drawText("These emojis have something to tell you, click each to find out!", (screen_width - 650) / 2, screen_height - 40, 20, .gray);
        rl.drawText("Each emoji is a unicode character from a font, not a texture... Press [SPACEBAR] to refresh", (screen_width - 484) / 2, screen_height - 16, 10, .gray);
    }
}

/// Fills the emoji array with random emojis (only those emojis present in fontEmoji)
fn randomizeEmoji(emojis: []Emoji) void {
    const start = rl.getRandomValue(45, 360);

    for (emojis, 1..) |*emoji, n| {
        emoji.index = @intCast(rl.getRandomValue(0, emoji_codepoints.len - 1));

        // Generate a random color for this emoji
        const hue: f32 = @floatFromInt(@mod(start * @as(i32, @intCast(n)), 360));
        emoji.color = rl.fade(rl.colorFromHSV(hue, 0.6, 0.85), 0.8);

        // Set a random message for this emoji
        emoji.message = @intCast(rl.getRandomValue(0, messages.len - 1));
    }
}

/// Draw text using font inside rectangle limits
fn drawTextBoxed(font: rl.Font, text: [:0]const u8, rec: rl.Rectangle, font_size: f32, spacing: f32, word_wrap: bool, tint: rl.Color) void {
    drawTextBoxedSelectable(font, text, rec, font_size, spacing, word_wrap, tint, 0, 0, .white, .white);
}

/// Draw text using font inside rectangle limits with support for text selection
fn drawTextBoxedSelectable(
    font: rl.Font,
    text: [:0]const u8,
    rec: rl.Rectangle,
    font_size: f32,
    spacing: f32,
    word_wrap: bool,
    tint: rl.Color,
    select_start_in: i32,
    select_length: i32,
    select_tint: rl.Color,
    select_back_tint: rl.Color,
) void {
    var select_start = select_start_in;
    const length: i32 = @intCast(text.len); // Total length in bytes of the text, scanned by codepoints in loop

    var text_offset_y: f32 = 0.0; // Offset between lines (on line break '\n')
    var text_offset_x: f32 = 0.0; // Offset X to next character to draw

    const base_size: f32 = @floatFromInt(font.baseSize);
    const scale_factor = font_size / base_size; // Character rectangle scaling factor
    const line_advance = (base_size + base_size / 2) * scale_factor;

    // Word/character wrapping mechanism variables
    const State = enum { measure, draw };
    var state: State = if (word_wrap) .measure else .draw;

    var start_line: i32 = -1; // Index where to begin drawing (where a line begins)
    var end_line: i32 = -1; // Index where to stop drawing (where a line ends)
    var lastk: i32 = -1; // Holds last value of the character position

    var i: i32 = 0;
    var k: i32 = 0;
    while (i < length) : ({
        i += 1;
        k += 1;
    }) {
        // Get next codepoint from byte string and glyph index in font
        const next = rl.getCodepoint(text[@intCast(i)..]);
        const codepoint = next.codepoint;
        const index: usize = @intCast(rl.getGlyphIndex(font, codepoint));

        // NOTE: Normally we exit the decoding sequence as soon as a bad byte is found (and return 0x3f)
        // but we need to draw all of the bad bytes using the '?' symbol moving one byte
        const codepoint_byte_count = if (codepoint == 0x3f) 1 else next.size;
        i += (codepoint_byte_count - 1);

        var glyph_width: f32 = 0;
        if (codepoint != '\n') {
            const advance_x = font.glyphs.?[index].advanceX;
            glyph_width = if (advance_x == 0)
                font.recs.?[index].width * scale_factor
            else
                @as(f32, @floatFromInt(advance_x)) * scale_factor;

            if (i + 1 < length) glyph_width = glyph_width + spacing;
        }

        // NOTE: When wordWrap is ON we first measure how much of the text we can draw before going outside of the rec container
        // We store this info in startLine and endLine, then we change states, draw the text between those two variables
        // and change states again and again recursively until the end of the text (or until we get outside of the container)
        // When wordWrap is OFF we don't need the measure state so we go to the drawing state immediately
        // and begin drawing on the next line before we can get outside the container
        switch (state) {
            .measure => {
                // TODO: There are multiple types of spaces in UNICODE, maybe it's a good idea to add support for more
                // Ref: http://jkorpela.fi/chars/spaces.html
                if (codepoint == ' ' or codepoint == '\t' or codepoint == '\n') end_line = i;

                if ((text_offset_x + glyph_width) > rec.width) {
                    end_line = if (end_line < 1) i else end_line;
                    if (i == end_line) end_line -= codepoint_byte_count;
                    if ((start_line + codepoint_byte_count) == end_line) end_line = (i - codepoint_byte_count);

                    state = .draw;
                } else if ((i + 1) == length) {
                    end_line = i;
                    state = .draw;
                } else if (codepoint == '\n') state = .draw;

                if (state == .draw) {
                    text_offset_x = 0;
                    i = start_line;
                    glyph_width = 0;

                    // Save character position when we switch states
                    const tmp = lastk;
                    lastk = k - 1;
                    k = tmp;
                }
            },
            .draw => {
                if (codepoint == '\n') {
                    if (!word_wrap) {
                        text_offset_y += line_advance;
                        text_offset_x = 0;
                    }
                } else {
                    if (!word_wrap and ((text_offset_x + glyph_width) > rec.width)) {
                        text_offset_y += line_advance;
                        text_offset_x = 0;
                    }

                    // When text overflows rectangle height limit, just stop drawing
                    if ((text_offset_y + base_size * scale_factor) > rec.height) break;

                    // Draw selection background
                    var is_glyph_selected = false;
                    if (select_start >= 0 and k >= select_start and k < (select_start + select_length)) {
                        rl.drawRectangleRec(.{ .x = rec.x + text_offset_x - 1, .y = rec.y + text_offset_y, .width = glyph_width, .height = base_size * scale_factor }, select_back_tint);
                        is_glyph_selected = true;
                    }

                    // Draw current character glyph
                    if (codepoint != ' ' and codepoint != '\t') {
                        rl.drawTextCodepoint(font, codepoint, .{ .x = rec.x + text_offset_x, .y = rec.y + text_offset_y }, font_size, if (is_glyph_selected) select_tint else tint);
                    }
                }

                if (word_wrap and i == end_line) {
                    text_offset_y += line_advance;
                    text_offset_x = 0;
                    start_line = end_line;
                    end_line = -1;
                    glyph_width = 0;
                    select_start += lastk - k;
                    k = lastk;

                    state = .measure;
                }
            },
        }

        if (text_offset_x != 0 or codepoint != ' ') text_offset_x += glyph_width; // avoid leading spaces
    }
}
