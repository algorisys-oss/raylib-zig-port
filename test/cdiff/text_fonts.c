// text_fonts.c — C-vs-Zig differential for the rest of rtext.
//
// text_strings.c and font_data.c cover the case converters, insert/replace/
// split and LoadFontData. This program covers everything else rtext exports
// that the examples gate cannot pin down byte for byte: TextFormat's rotating
// buffers and truncation, number parsing, the remaining string functions and
// their overflow warnings, the UTF-8 codepoint functions on malformed input,
// every font loader (TTF, BMFont, XNA image fonts, crafted BMFont files with
// hex numbers, extra pages and missing fields), GenImageFontAtlas with both
// packers and atlas growth, measuring, glyph lookup, ExportFontAsCode's full
// output, and drawing (CRC of the framebuffer). Every TraceLog line goes
// through a callback, so log text is compared too. Needs a display
// (tools/cdiff.sh sets llvmpipe). Run via tools/cdiff.sh <oracle> <zig> <resources dir>.
#define _XOPEN_SOURCE 700
#include <ftw.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "raylib.h"

static const char *resDir = NULL;
static char pathBuf[4096];

static const char *Res(const char *name)
{
    snprintf(pathBuf, sizeof(pathBuf), "%s/%s", resDir, name);
    return pathBuf;
}

static void logCallback(int level, const char *text, va_list args)
{
    char line[2048];
    vsnprintf(line, sizeof(line), text, args);
    // Resource paths are the same in both runs; keep only the file name part
    // so output does not depend on where the resources live.
    const char *res = strstr(line, resDir);
    if (res != NULL)
    {
        printf("  log %d: %.*s<res>%s\n", level, (int)(res - line), line, res + strlen(resDir));
    }
    else printf("  log %d: %s\n", level, line);
}

static uint32_t Hash(const void *data, size_t size)
{
    const unsigned char *p = data;
    uint32_t h = 2166136261u;
    for (size_t i = 0; (p != NULL) && (i < size); i++) h = (h ^ p[i])*16777619u;
    return h;
}

static void PrintText(const char *what, const char *text)
{
    if (text != NULL) printf("%s: [%s]\n", what, text);
    else printf("%s: NULL\n", what);
}

static void PrintImage(const char *what, Image image)
{
    int size = (image.data != NULL)? GetPixelDataSize(image.width, image.height, image.format) : 0;
    printf("%s: %dx%d fmt=%d mip=%d %s h=%08x\n", what, image.width, image.height, image.format, image.mipmaps,
        (image.data != NULL)? "D" : "-", Hash(image.data, size));
}

static bool printPixels = true;

static void PrintFont(const char *what, Font font)
{
    printf("%s: base=%d count=%d pad=%d tex=%dx%d fmt=%d valid=%d default=%d\n", what, font.baseSize, font.glyphCount,
        font.glyphPadding, font.texture.width, font.texture.height, font.texture.format, IsFontValid(font),
        font.texture.id == GetFontDefault().texture.id);
    if ((font.texture.id != 0) && printPixels)
    {
        Image atlas = LoadImageFromTexture(font.texture);
        PrintImage(" atlas", atlas);
        UnloadImage(atlas);
    }
    uint32_t recHash = 2166136261u, glyphHash = 2166136261u;
    for (int i = 0; i < font.glyphCount; i++)
    {
        recHash = recHash*31 + Hash(&font.recs[i], sizeof(Rectangle));
        GlyphInfo g = font.glyphs[i];
        int size = (g.image.data != NULL)? GetPixelDataSize(g.image.width, g.image.height, g.image.format) : 0;
        glyphHash = glyphHash*31 + (uint32_t)g.value*7 + (uint32_t)g.offsetX*11 + (uint32_t)g.offsetY*13 + (uint32_t)g.advanceX*17 +
            (uint32_t)g.image.width*19 + (uint32_t)g.image.height*23 + (uint32_t)g.image.format*29 + (printPixels? Hash(g.image.data, size) : 0);
    }
    printf(" recs=%08x glyphs=%08x\n", recHash, glyphHash);
    for (int i = 0; (i < font.glyphCount) && (i < 4); i++)
    {
        printf(" g%d v=%d off=%d,%d adv=%d rec=%g,%g,%g,%g\n", i, font.glyphs[i].value, font.glyphs[i].offsetX,
            font.glyphs[i].offsetY, font.glyphs[i].advanceX, font.recs[i].x, font.recs[i].y, font.recs[i].width, font.recs[i].height);
    }

    const char *samples[] = { "", "A", "Hello, World!", "two\nlines\n", "\xe4\xbd\xa0\xe5\xa5\xbd \xc3\xa9t\xc3\xa9", "\xff\xfe bad", 0 };
    for (int k = 0; samples[k] != NULL; k++)
    {
        Vector2 m = MeasureTextEx(font, samples[k], (float)font.baseSize*1.5f, 1.25f);
        int count = 0;
        int *cps = LoadCodepoints(samples[k], &count);
        Vector2 mc = MeasureTextCodepoints(font, cps, count, 13.0f, 0.5f);
        UnloadCodepoints(cps);
        printf(" measure[%d] %a,%a cp %a,%a\n", k, m.x, m.y, mc.x, mc.y);
    }
    if (!IsFontValid(font)) return; // GetGlyphInfo reads glyphs[0] unchecked
    int probes[] = { 0, 32, 63, 65, 0xe9, 0x4f60, 0x1f600, -5, 0x110000 };
    for (int k = 0; k < (int)(sizeof(probes)/sizeof(probes[0])); k++)
    {
        GlyphInfo g = GetGlyphInfo(font, probes[k]);
        Rectangle r = GetGlyphAtlasRec(font, probes[k]);
        printf(" glyph %x -> %d v=%d rec=%g,%g,%g,%g\n", probes[k], GetGlyphIndex(font, probes[k]), g.value, r.x, r.y, r.width, r.height);
    }
}

static void PrintFile(const char *what, const char *fileName)
{
    char *text = LoadFileText(fileName);
    printf("%s: %s\n", what, (text != NULL)? "" : "NULL");
    if (text != NULL) printf("%s<EOF>\n", text);
    UnloadFileText(text);
}

static uint32_t crc32(const unsigned char *p, size_t n)
{
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) { c ^= p[i]; for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (uint32_t)(-(int)(c & 1))); }
    return c ^ 0xFFFFFFFFu;
}

static int removeEntry(const char *path, const struct stat *st, int flag, struct FTW *ftw)
{
    (void)st; (void)flag; (void)ftw;
    return remove(path);
}

static void Strings(void)
{
    printf("== TextFormat\n");
    const char *f[6];
    for (int i = 0; i < 6; i++) f[i] = TextFormat("fmt %d %s %5.2f %x", i, "s", i*1.5, i*255);
    for (int i = 0; i < 6; i++) PrintText("fmt", f[i]); // the first two were overwritten by the rotation
    PrintText("fmt null", TextFormat(NULL));
    static char longText[3000];
    memset(longText, 'x', sizeof(longText) - 1);
    const char *t = TextFormat("%s", longText);
    printf("trunc len=%u tail=[%s]\n", TextLength(t), t + 1015);
    t = TextFormat("%.1022s", longText);
    printf("exact1022 len=%u tail=[%s]\n", TextLength(t), t + 1018);
    t = TextFormat("%.1023s", longText);
    printf("exact1023 len=%u tail=[%s]\n", TextLength(t), t + 1018);
    t = TextFormat("%.1024s", longText);
    printf("exact1024 len=%u tail=[%s]\n", TextLength(t), t + 1018);
    printf("len null=%u empty=%u\n", TextLength(NULL), TextLength(""));

    printf("== numbers\n");
    const char *nums[] = { "", "0", "42", "-42", "+7", "--3", "12abc", "3.25", "-0.5", ".5", "1.", "1e5", "007", "0x1f",
        " 5", "2147483647", "2147483648", "99999999999", "123.456789", "-", "+", "1.2.3", "9.999999999", 0 };
    for (int i = 0; nums[i]; i++) printf("[%s] int=%d float=%a\n", nums[i], TextToInteger(nums[i]), TextToFloat(nums[i]));
    printf("null int=%d float=%a\n", TextToInteger(NULL), TextToFloat(NULL));

    printf("== copy/equal/append/find\n");
    char dst[64] = "zzzzzzzz";
    printf("copy=%d [%s]\n", TextCopy(dst, "abc"), dst);
    printf("copy empty=%d [%s]\n", TextCopy(dst, ""), dst);
    printf("copy null=%d\n", TextCopy(dst, NULL));
    printf("equal %d %d %d %d %d\n", TextIsEqual("a", "a"), TextIsEqual("a", "b"), TextIsEqual("a", "ab"), TextIsEqual(NULL, "a"), TextIsEqual("", ""));
    char app[64] = { 0 };
    int pos = 0;
    TextAppend(app, "hello", &pos); TextAppend(app, ", ", &pos); TextAppend(app, "", &pos); TextAppend(app, NULL, &pos); TextAppend(app, "world", &pos);
    printf("append pos=%d [%s]\n", pos, app);
    printf("find %d %d %d %d %d\n", TextFindIndex("hello world", "o"), TextFindIndex("hello world", "world"),
        TextFindIndex("hello", "xyz"), TextFindIndex("hello", ""), TextFindIndex(NULL, "a"));

    printf("== case/spaces\n");
    const char *cs[] = { "", "Hello World 123 _-!", "\xc3\xa9t\xc3\xa9 MiXeD", "  a b  c ", 0 };
    for (int i = 0; cs[i]; i++)
    {
        printf("[%s] U=[%s] L=[%s] R=[%s]\n", cs[i], TextToUpper(cs[i]), TextToLower(cs[i]), TextRemoveSpaces(cs[i]));
    }
    printf("null U=[%s] L=[%s] R=[%s]\n", TextToUpper(NULL), TextToLower(NULL), TextRemoveSpaces(NULL));
    static char big[1500];
    for (int i = 0; i < (int)sizeof(big) - 1; i++) big[i] = (i%7 == 0)? ' ' : 'a' + i%26;
    printf("big U=%u L=%u R=%u P=%u C=%u S=%u\n", TextLength(TextToUpper(big)), TextLength(TextToLower(big)),
        TextLength(TextRemoveSpaces(big)), TextLength(TextToPascal(big)), TextLength(TextToCamel(big)), TextLength(TextToSnake(big)));

    printf("== between/replace\n");
    const char *rb[][4] = {
        { "start [middle] end", "[", "]", "NEW" }, { "start [middle] end", "[", "]", NULL }, { "start [middle] end", "[", "]", "" },
        { "a<<b>>c<<d>>e", "<<", ">>", "X" }, { "no markers", "[", "]", "X" }, { "[only begin", "[", "]", "X" },
        { "[]", "[", "]", "fill" }, { "x[y]z", "", "]", "Q" }, { "", "[", "]", "X" },
    };
    for (int i = 0; i < (int)(sizeof(rb)/sizeof(rb[0])); i++)
    {
        printf("[%s] between=[%s]", rb[i][0], GetTextBetween(rb[i][0], rb[i][1], rb[i][2]));
        printf(" rb=[%s]", TextReplaceBetween(rb[i][0], rb[i][1], rb[i][2], rb[i][3]));
        char *a = TextReplaceBetweenAlloc(rb[i][0], rb[i][1], rb[i][2], rb[i][3]);
        printf(" rba=[%s]\n", a? a : "NULL");
        MemFree(a);
    }
    printf("rb null text=[%s] null begin=[%s]\n", TextReplaceBetween(NULL, "[", "]", "x"), TextReplaceBetween("a[b]c", NULL, "]", "x"));
    printf("rba null=%s\n", TextReplaceBetweenAlloc("a[b]c", "[", NULL, "x")? "ptr" : "NULL");
    static char huge[1200];
    memset(huge, 'h', sizeof(huge) - 1);
    huge[10] = '[';
    huge[1100] = ']';
    printf("between huge len=%u\n", TextLength(GetTextBetween(huge, "[", "]")));
    huge[1100] = 'h';
    huge[1150] = ']';
    printf("between huge2 len=%u\n", TextLength(GetTextBetween(huge, "[", "]")));
    huge[1150] = 'h';
    huge[20] = ']';
    printf("rb huge len=%u\n", TextLength(TextReplaceBetween(huge, "[", "]", "y")));
    char *hugeAlloc = TextReplaceBetweenAlloc(huge, "[", "]", "yyy");
    printf("rba huge len=%u h=%08x\n", TextLength(hugeAlloc), Hash(hugeAlloc, TextLength(hugeAlloc)));
    MemFree(hugeAlloc);
    huge[20] = 'h';
    printf("replace huge=[%u]\n", TextLength(TextReplace(huge, "hh", "HHH")));
    char *ra = TextReplaceAlloc(huge, "hh", "HHH");
    printf("replace alloc huge len=%u h=%08x\n", TextLength(ra), Hash(ra, TextLength(ra)));
    MemFree(ra);
    printf("replace null repl=[%s] empty search=[%s] null=[%s]\n", TextReplace("a-b-c", "-", NULL), TextReplace("abc", "", "x"), TextReplace(NULL, "a", "b"));
    ra = TextReplaceAlloc("a-b-c", "-", NULL);
    printf("replace alloc null repl=[%s]\n", ra);
    MemFree(ra);
    printf("replace alloc empty=%s\n", TextReplaceAlloc("abc", "", "x")? "ptr" : "NULL");
    printf("insert huge=[%u]\n", TextLength(TextInsert(huge, "x", 5)));
    char *ia = TextInsertAlloc(huge, "xyz", 2000);
    printf("insert alloc huge len=%u h=%08x\n", TextLength(ia), Hash(ia, TextLength(ia)));
    MemFree(ia);
    printf("insert null=[%s] alloc=%s\n", TextInsert("abc", NULL, 1), TextInsertAlloc(NULL, "x", 0)? "ptr" : "NULL");

    printf("== join/split\n");
    char *parts[200];
    static char words[200][8];
    for (int i = 0; i < 200; i++) { snprintf(words[i], 8, "w%03d", i); parts[i] = words[i]; }
    printf("join0=[%s]\n", TextJoin(parts, 0, ","));
    printf("join1=[%s]\n", TextJoin(parts, 1, ","));
    printf("join nodelim=[%s]\n", TextJoin(parts, 5, ""));
    const char *joined = TextJoin(parts, 200, ", ");
    printf("join200 len=%u tail=[%s]\n", TextLength(joined), joined + TextLength(joined) - 12);
    char *withNull[] = { "a", NULL, "c" };
    printf("join null entry=[%s]\n", TextJoin(withNull, 3, "+"));
    static char many[600];
    for (int i = 0; i < 599; i++) many[i] = (i%3 == 2)? ';' : 'a' + i%26;
    int count = 0;
    char **split = TextSplit(many, ';', &count);
    printf("split many=%d last=[%s] first=[%s]\n", count, split[count - 1], split[0]);
    split = TextSplit("a,,b,", ',', &count);
    printf("split edges=%d:", count);
    for (int i = 0; i < count; i++) printf("{%s}", split[i]);
    printf("\n");
    split = TextSplit(NULL, ',', &count);
    printf("split null=%d first=[%s]\n", count, split[0]);
    split = TextSplit("", ',', &count);
    printf("split empty=%d first=[%s]\n", count, split[0]);
    split = TextSplit("abc", '\0', &count);
    printf("split nul delim=%d first=[%s]\n", count, split[0]);

    printf("== lines\n");
    const char *ls[] = { "", "one", "a\n", "\n\n", "x\ny\r\nz", 0 };
    for (int i = 0; ls[i]; i++)
    {
        char **lines = LoadTextLines(ls[i], &count);
        printf("lines=%d:", count);
        for (int k = 0; k < count; k++) printf("<%s>", lines[k]);
        printf("\n");
        UnloadTextLines(lines, count);
    }
    char **nl = LoadTextLines(NULL, &count);
    printf("lines null=%d %s\n", count, nl? "ptr" : "NULL");
}

static void Codepoints(void)
{
    printf("== codepoints\n");
    int cps[] = { 0, 1, 0x41, 0x7f, 0x80, 0x7ff, 0x800, 0xd800, 0xffff, 0x10000, 0x10ffff, 0x110000, -1, 0x7fffffff };
    int n = (int)(sizeof(cps)/sizeof(cps[0]));
    for (int i = 0; i < n; i++)
    {
        int size = -1;
        const char *u = CodepointToUTF8(cps[i], &size);
        printf("cp %x size=%d bytes=%02x %02x %02x %02x %02x %02x\n", cps[i], size, (unsigned char)u[0], (unsigned char)u[1],
            (unsigned char)u[2], (unsigned char)u[3], (unsigned char)u[4], (unsigned char)u[5]);
    }
    char *utf8 = LoadUTF8(cps + 2, n - 2);
    printf("LoadUTF8 len=%u h=%08x\n", TextLength(utf8), Hash(utf8, TextLength(utf8) + 1));
    UnloadUTF8(utf8);
    printf("LoadUTF8 0=%s null=%s\n", LoadUTF8(cps, 0)? "ptr" : "NULL", LoadUTF8(NULL, 3)? "ptr" : "NULL");

    const char *seqs[] = {
        "A", "\xc3\xa9", "\xe4\xbd\xa0", "\xf0\x9f\x98\x80", "\xc0\x80", "\xc1\xbf", "\xc3", "\xc3(", "\xe0\x80\x80", "\xe0\xa0\x80",
        "\xed\xa0\x80", "\xed\x9f\xbf", "\xe4\xbd", "\xe4(x", "\xf0\x80\x80\x80", "\xf0\x90\x80\x80", "\xf4\x8f\xbf\xbf",
        "\xf4\x90\x80\x80", "\xf5\x80\x80\x80", "\xf8\x88\x80\x80\x80", "\x80", "\xbf", "\xfe", "\xff", "\xf0\x9f\x98", "\xf0\x9f", "\xf0", "", 0
    };
    for (int i = 0; seqs[i]; i++)
    {
        int s1 = -1, s2 = -1;
        int c1 = GetCodepoint(seqs[i], &s1);
        int c2 = GetCodepointNext(seqs[i], &s2);
        int count = 0;
        int *all = LoadCodepoints(seqs[i], &count);
        printf("seq %d get=%x/%d next=%x/%d count=%d/%d", i, c1, s1, c2, s2, count, GetCodepointCount(seqs[i]));
        for (int k = 0; k < count; k++) printf(" %x", all[k]);
        printf("\n");
        UnloadCodepoints(all);
    }
    int s = -1;
    printf("null get=%x/%d", GetCodepoint(NULL, &s), s);
    printf(" next=%x/%d", GetCodepointNext(NULL, &s), s);
    printf(" prev=%x/%d count=%d\n", GetCodepointPrevious(NULL, &s), s, GetCodepointCount(NULL));
    int count = -1;
    printf("LoadCodepoints null=%s count=%d\n", LoadCodepoints(NULL, &count)? "ptr" : "NULL", count);

    // Walk backwards over a mixed string
    const char *mixed = "\0a\xc3\xa9\xe4\xbd\xa0\xf0\x9f\x98\x80z";
    const char *end = mixed + 1 + 11;
    const char *p = end;
    while (p > mixed + 1)
    {
        int size = -1;
        int cp = GetCodepointPrevious(p, &size);
        printf(" prev %x/%d", cp, size);
        p -= size;
    }
    printf("\n");
}

static Font Load(const char *what, const char *fileName)
{
    printf("-- %s\n", what);
    Font font = LoadFont(fileName);
    PrintFont(what, font);
    return font;
}

static void Fonts(void)
{
    printf("== fonts\n");
    Font def = GetFontDefault();
    PrintFont("default", def);
    printf("MeasureText %d %d %d %d\n", MeasureText("Hello", 5), MeasureText("Hello", 20), MeasureText("a\nbb\nccc", 33), MeasureText("", 20));

    // TTF and BMFont resources, and XNA style image fonts
    Font fonts[16];
    int fc = 0;
    fonts[fc++] = Load("pixantiqua.ttf", Res("pixantiqua.ttf"));
    fonts[fc++] = Load("pixantiqua.fnt", Res("pixantiqua.fnt"));
    fonts[fc++] = Load("dejavu.fnt", Res("dejavu.fnt"));
    fonts[fc++] = Load("symbola.fnt", Res("symbola.fnt"));
    fonts[fc++] = Load("custom_mecha.png", Res("custom_mecha.png"));
    fonts[fc++] = Load("custom_alagard.png", Res("custom_alagard.png"));
    fonts[fc++] = Load("custom_jupiter_crash.png", Res("custom_jupiter_crash.png"));
    fonts[fc++] = Load("missing.ttf", "missing.ttf");
    fonts[fc++] = Load("missing.png", "missing.png");

    printf("-- LoadFontEx codepoints\n");
    int cps[] = { 'A', 'B', 0xe9, 0x4f60, 0x20, 0x3000, '?' };
    Font ex = LoadFontEx(Res("NotoSansTC-Regular.ttf"), 20, cps, 7);
    PrintFont("noto ex", ex);
    fonts[fc++] = ex;
    ex = LoadFontEx(Res("anonymous_pro_bold.ttf"), 0, NULL, 0);
    PrintFont("anonymous size0", ex);
    fonts[fc++] = ex;

    printf("-- LoadFontFromMemory\n");
    int dataSize = 0;
    unsigned char *data = LoadFileData(Res("DotGothic16-Regular.ttf"), &dataSize);
    Font mem = LoadFontFromMemory(".TTF", data, dataSize, 18, NULL, 40);
    PrintFont("memory .TTF", mem);
    fonts[fc++] = mem;
    mem = LoadFontFromMemory(".woff", data, dataSize, 18, NULL, 40);
    PrintFont("memory .woff", mem);

    printf("-- GenImageFontAtlas\n");
    int glyphCount = 0;
    GlyphInfo *glyphs = LoadFontData(data, dataSize, 30, NULL, 120, FONT_DEFAULT, &glyphCount);
    int pads[] = { 0, 2, 7 };
    for (int pm = 0; pm <= 2; pm++)
    {
        for (int pi = 0; pi < 3; pi++)
        {
            Rectangle *recs = NULL;
            Image atlas = GenImageFontAtlas(glyphs, &recs, glyphCount, 30, pads[pi], pm);
            printf("pack=%d pad=%d recs=%08x ", pm, pads[pi], (pm <= 1)? Hash(recs, glyphCount*sizeof(Rectangle)) : 0);
            PrintImage("atlas", atlas);
            UnloadImage(atlas);
            MemFree(recs);
        }
    }
    // A font size far below the glyph sizes makes the basic packer grow the atlas
    Rectangle *recs = NULL;
    Image grown = GenImageFontAtlas(glyphs, &recs, glyphCount, 4, 1, 0);
    printf("grown recs=%08x ", Hash(recs, glyphCount*sizeof(Rectangle)));
    PrintImage("atlas", grown);
    UnloadImage(grown);
    MemFree(recs);
    recs = (Rectangle *)1;
    Image none = GenImageFontAtlas(NULL, &recs, 10, 20, 0, 0);
    printf("null glyphs recs=%s ", (recs == (Rectangle *)1)? "untouched" : "changed");
    PrintImage("atlas", none);
    UnloadFontData(glyphs, glyphCount);
    UnloadFontData(NULL, 3);
    UnloadFileData(data);

    printf("-- ExportFontAsCode\n");
    printf("export default=%d\n", ExportFontAsCode(def, "default_font.h"));
    PrintFile("default_font.h", "default_font.h");
    printf("export pixantiqua=%d\n", ExportFontAsCode(fonts[0], "my_pix-antiqua font.h"));
    PrintFile("my_pix-antiqua font.h", "my_pix-antiqua font.h");
    printf("export fnt=%d\n", ExportFontAsCode(fonts[1], "dir/missing/out.h"));

    printf("-- drawing\n");
    RenderTexture2D target = LoadRenderTexture(320, 240);
    for (int i = 0; i < fc; i++)
    {
        if (!IsFontValid(fonts[i])) continue; // DrawTextCodepoint reads glyphs[0] unchecked
        BeginTextureMode(target);
        ClearBackground(RAYWHITE);
        DrawText("Default font text\nsecond line", 4, 4, 10, MAROON);
        DrawText("Big", 4, 40, 31, DARKBLUE);
        DrawTextEx(fonts[i], "Hello \xc3\xa9t\xc3\xa9\n\tnext \xe4\xbd\xa0!", (Vector2){ 10.5f, 80.25f }, (float)fonts[i].baseSize*0.8f, 1.5f, BLACK);
        DrawTextPro(fonts[i], "Rotated", (Vector2){ 200, 150 }, (Vector2){ 10, 5 }, 33.0f, 20.0f, 2.0f, RED);
        int cp[] = { 'C', 'o', 'd', 'e', '\n', ' ', 0x4f60, '\t', 'x' };
        DrawTextCodepoints(fonts[i], cp, 9, (Vector2){ 10, 170 }, 18.0f, 1.0f, DARKGREEN);
        DrawTextCodepoint(fonts[i], 'Q', (Vector2){ 280, 10 }, 40.0f, PURPLE);
        SetTextLineSpacing(i%3 * 4);
        EndTextureMode();
        Image shot = LoadImageFromTexture(target.texture);
        printf("draw %d crc=%08x\n", i, crc32(shot.data, GetPixelDataSize(shot.width, shot.height, shot.format)));
        UnloadImage(shot);
    }
    UnloadRenderTexture(target);
    SetTextLineSpacing(2);

    for (int i = 0; i < fc; i++) UnloadFont(fonts[i]);
}

// Crafted BMFont files: numbers glibc's %i reads (hex, octal, signs), extra
// spacing, pages beyond the 8 supported, files with fields missing.
static void BMFonts(void)
{
    printf("== crafted BMFont\n");
    int size = 0;
    unsigned char *png = LoadFileData(Res("pixantiqua.png"), &size);
    SaveFileData("atlas.png", png, size);
    UnloadFileData(png);
    // An 8-bit grayscale atlas exercises the GRAYSCALE -> GRAY_ALPHA path
    Image gray = GenImageGradientLinear(64, 64, 45, BLACK, WHITE);
    ImageFormat(&gray, PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
    ExportImage(gray, "gray.png");
    UnloadImage(gray);

    const char *files[][2] = {
        { "basic.fnt",
          "info face=\"x\"\ncommon lineHeight=32 base=27 scaleW=512 scaleH=512 pages=1\npage id=0 file=\"atlas.png\"\nchars count=3\n"
          "char id=65   x=0 y=0 width=10 height=12 xoffset=1 yoffset=-2 xadvance=11 page=0\n"
          "char id=0x42 x=0x10 y=010 width=+9 height=12 xoffset=-0x1 yoffset=0 xadvance=10 page=0\n"
          "char id=67 x= 30 y=  0 width=8\theight=12 xoffset=0 yoffset=0 xadvance=9 page=0  chnl=15\n" },
        { "noeol.fnt",
          "info\ncommon lineHeight=20 base=16 scaleW=512 scaleH=512 pages=1\npage id=0 file=\"atlas.png\"\nchars count=1\n"
          "char id=97 x=1 y=2 width=3 height=4 xoffset=5 yoffset=6 xadvance=7 page=0" },
        { "pages.fnt",
          "info\ncommon lineHeight=16 base=12 scaleW=64 scaleH=64 pages=3\npage id=0 file=\"gray.png\"\npage id=1 file=\"atlas.png\"\n"
          "page id=2 file=\"gray.png\"\nchars count=2\n"
          "char id=49 x=0 y=0 width=8 height=8 xoffset=0 yoffset=0 xadvance=8 page=2\n"
          "char id=50 x=8 y=8 width=8 height=8 xoffset=0 yoffset=0 xadvance=8 page=1\n" },
        { "toomany.fnt",
          "info\ncommon lineHeight=16 base=12 scaleW=64 scaleH=64 pages=10\npage id=0 file=\"gray.png\"\npage id=1 file=\"gray.png\"\n"
          "page id=2 file=\"gray.png\"\npage id=3 file=\"gray.png\"\npage id=4 file=\"gray.png\"\npage id=5 file=\"gray.png\"\n"
          "page id=6 file=\"gray.png\"\npage id=7 file=\"gray.png\"\nchars count=1\n"
          "char id=49 x=0 y=0 width=8 height=8 xoffset=0 yoffset=0 xadvance=8 page=7\n" },
        { "short_common.fnt", "info\ncommon lineHeight=16 base=12 scaleW=64\npage id=0 file=\"atlas.png\"\nchars count=1\n" },
        { "four_common.fnt",
          "info\ncommon lineHeight=16 base=12 scaleW=64 scaleH=64 \npage id=0 file=\"atlas.png\"\nchars count=1\n"
          "char id=49 x=0 y=0 width=8 height=8 xoffset=0 yoffset=0 xadvance=8 page=0\n" },
        { "nofile.fnt", "info\ncommon lineHeight=16 base=12 scaleW=64 scaleH=64 pages=1\npage id=0 file=\"\"\nchars count=1\n" },
        { "nocount.fnt", "info\ncommon lineHeight=16 base=12 scaleW=64 scaleH=64 pages=1\npage id=0 file=\"atlas.png\"\nchars count=x\n" },
        { "badimage.fnt",
          "info\ncommon lineHeight=16 base=12 scaleW=64 scaleH=64 pages=1\npage id=0 file=\"nothere.png\"\nchars count=1\n"
          "char id=49 x=0 y=0 width=8 height=8 xoffset=0 yoffset=0 xadvance=8 page=0\n" },
        { "longname.fnt",
          "info\ncommon lineHeight=16 base=12 scaleW=64 scaleH=64 pages=1\n"
          "page id=0 file=\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png\"\n"
          "chars count=1\nchar id=49 x=0 y=0 width=8 height=8 xoffset=0 yoffset=0 xadvance=8 page=0\n" },
        { "crlf.fnt",
          "info\r\ncommon lineHeight=16 base=12 scaleW=64 scaleH=64 pages=1\r\npage id=0 file=\"atlas.png\"\r\nchars count=1\r\n"
          "char id=49 x=0 y=0 width=8 height=8 xoffset=0 yoffset=0 xadvance=8 page=0\r\n" },
    };
    for (int i = 0; i < (int)(sizeof(files)/sizeof(files[0])); i++)
    {
        SaveFileText(files[i][0], (char *)files[i][1]);
        // raylib 6.2 unloads pages 1.. before drawing them into the merged
        // atlas (a use-after-free), so multi-page pixels are undefined in C
        printPixels = (strstr(files[i][1], "pages=1\n") != NULL) || (strstr(files[i][1], "pages=1\r") != NULL);
        Font font = Load(files[i][0], files[i][0]);
        UnloadFont(font);
    }
    printPixels = true;
}

int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    resDir = argv[1];

    char root[] = "/tmp/rltextfonts_XXXXXX";
    if (!mkdtemp(root) || chdir(root) != 0) return 2;

    SetTraceLogLevel(LOG_ALL);
    SetTraceLogCallback(logCallback);

    Strings();
    Codepoints();

    SetTraceLogLevel(LOG_WARNING); // window/GL setup logs are not rtext's
    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(320, 240, "text_fonts");
    SetTraceLogLevel(LOG_ALL);

    Fonts();
    BMFonts();

    SetTraceLogLevel(LOG_WARNING);
    CloseWindow();

    if (chdir("/") == 0) nftw(root, removeEntry, 8, FTW_DEPTH | FTW_PHYS);
    return 0;
}
