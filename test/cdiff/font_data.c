// font_data.c — C-vs-Zig differential for rtext's LoadFontData.
//
// For each TTF given on the command line: default, bitmap and SDF glyph
// generation (FONT_SDF is only drawn by text_font_sdf while SPACE is held, so
// the examples gate never reached it) over ASCII plus every Unicode space
// codepoint 6.2 special-cases. Prints metrics and a hash of each glyph image.
// Run via tools/cdiff.sh <oracle> <zig> <font.ttf>...
#include <stdio.h>
#include "raylib.h"

static const int codepoints[] = {
    0x20, 0x41, 0xA0, 0x1680, 0x2000, 0x2005, 0x2009, 0x200A, 0x202F, 0x205F, 0x3000,
};
#define CODEPOINT_COUNT ((int)(sizeof(codepoints)/sizeof(codepoints[0])))

int main(int argc, char **argv)
{
    SetTraceLogLevel(LOG_NONE);

    for (int a = 1; a < argc; a++)
    {
        int dataSize = 0;
        unsigned char *data = LoadFileData(argv[a], &dataSize);

        for (int type = FONT_DEFAULT; type <= FONT_SDF; type++)
        {
            int glyphCount = 0;
            GlyphInfo *glyphs = LoadFontData(data, dataSize, 24, codepoints, CODEPOINT_COUNT, type, &glyphCount);
            printf("%s type=%d count=%d\n", argv[a], type, glyphCount);

            for (int i = 0; i < glyphCount; i++)
            {
                const unsigned char *pixels = glyphs[i].image.data;
                unsigned int hash = 0;
                for (int k = 0; (pixels != NULL) && (k < glyphs[i].image.width*glyphs[i].image.height); k++) hash = hash*31 + pixels[k];

                printf(" %x adv=%d off=%d,%d %dx%d %s h=%08x\n", glyphs[i].value, glyphs[i].advanceX,
                    glyphs[i].offsetX, glyphs[i].offsetY, glyphs[i].image.width, glyphs[i].image.height,
                    (pixels != NULL)? "D" : "-", hash);
            }

            UnloadFontData(glyphs, glyphCount);
        }

        UnloadFileData(data);
    }

    return 0;
}
