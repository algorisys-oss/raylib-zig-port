// core_automation.c — C-vs-Zig differential for the automation events file.
//
// LoadAutomationEventList reads raylib's text format with fgets + sscanf, so
// its results depend on details of both: lines are read in chunks of at most
// 255 bytes, a last line without '\n' is never processed, a failed read
// leaves the previous line in the buffer, `c %i` accepts hex and octal, and
// an `e` line keeps whatever fields parsed before the first bad one. Each
// case writes exact bytes to a file, loads it and prints the list plus every
// TraceLog line. ExportAutomationEventList is checked by its file text and by
// a round trip. Runs in a fresh temp directory. Run via tools/cdiff.sh.
#define _XOPEN_SOURCE 700
#include <ftw.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "raylib.h"

static void logCallback(int level, const char *text, va_list args)
{
    printf("  log %d: ", level);
    vprintf(text, args);
    printf("\n");
}

static void writeBytes(const char *path, const char *bytes, size_t size)
{
    FILE *file = fopen(path, "wb");
    if (!file) exit(2);
    fwrite(bytes, 1, size, file);
    fclose(file);
}

static void printList(const char *what, AutomationEventList list)
{
    unsigned int sum = 0;
    for (unsigned int i = 0; i < list.count; i++) {
        AutomationEvent e = list.events[i];
        sum = sum*31 + e.frame; sum = sum*31 + e.type;
        for (int k = 0; k < 4; k++) sum = sum*31 + (unsigned int)e.params[k];
    }
    printf("%s: capacity=%u count=%u sum=%08x events=%s\n", what, list.capacity, list.count, sum, list.events ? "set" : "NULL");
    for (unsigned int i = 0; (i < list.count) && (i < 8); i++) {
        AutomationEvent e = list.events[i];
        printf("  [%u] frame=%u type=%u params=%d,%d,%d,%d\n", i, e.frame, e.type, e.params[0], e.params[1], e.params[2], e.params[3]);
    }
}

static void loadCase(const char *what, const char *bytes, size_t size)
{
    writeBytes("case.rae", bytes, size);
    printf("== %s\n", what);
    AutomationEventList list = LoadAutomationEventList("case.rae");
    printList(what, list);
    UnloadAutomationEventList(list);
}

#define CASE(what, literal) loadCase(what, literal, sizeof(literal) - 1)

static int removeEntry(const char *path, const struct stat *st, int flag, struct FTW *ftw)
{
    (void)st; (void)flag; (void)ftw;
    return remove(path);
}

int main(void)
{
    char root[] = "/tmp/rlautomation_XXXXXX";
    if (!mkdtemp(root) || chdir(root) != 0) return 2;

    SetTraceLogLevel(LOG_ALL);
    SetTraceLogCallback(logCallback);

    AutomationEventList list = LoadAutomationEventList(NULL);
    printList("null", list);
    UnloadAutomationEventList(list);
    list = LoadAutomationEventList("missing.rae");
    printList("missing", list);
    UnloadAutomationEventList(list);

    CASE("empty", "");
    CASE("newline only", "\n");
    CASE("normal", "# comment\n#\nc 3\ne 0 2 65 0 0 0 // Event: INPUT_KEY_DOWN\ne 10 3 66 0 0 0\ne 20 7 100 200 0 0\n");
    CASE("no final newline", "c 2\ne 1 2 3 4 5 6\ne 7 8 9 10 11 12");
    CASE("count mismatch", "c 5\ne 1 1 1 1 1 1\n");
    CASE("count after events", "e 1 1 1 1 1 1\ne 2 2 2 2 2 2\nc 2\n");
    CASE("two counts", "c 9\nc 1\ne 1 1 1 1 1 1\n");
    CASE("count hex", "c 0x1\ne 5 5 5 5 5 5\n");
    CASE("count octal", "c 010\n");
    CASE("count signs", "c -1\nc +4\n");
    CASE("count blank", "c\n");
    CASE("count word", "c x\n");
    CASE("count 0x", "c 0x\n");
    CASE("count 0xg", "c 0xg\n");
    CASE("count spaces", "c   \t 7\n");
    CASE("count glued", "c7\n");
    CASE("count huge", "c 99999999999\n");
    CASE("count big hex", "c 0xFFFFFFFF\n");
    // A prior count shows whether a later bad count assigns or leaves it
    CASE("count then 0x", "c 5\nc 0x\n");
    CASE("count then 0xg", "c 5\nc 0xg\n");
    CASE("count then 0x1g", "c 5\nc 0x1g\n");
    CASE("count then word", "c 5\nc x\n");
    CASE("count then -0x2", "c 5\nc -0x2\n");
    CASE("count then 09", "c 5\nc 09\n");
    CASE("count then 0", "c 5\nc 0\n");
    CASE("count then -", "c 5\nc -\n");
    CASE("count then 0X1F", "c 5\nc 0X1F\n");
    CASE("count beyond long", "c 5\nc 99999999999999999999\n");
    CASE("count beyond -long", "c 5\nc -99999999999999999999\n");
    CASE("event beyond long", "e 99999999999999999999 -99999999999999999999 1 1 1 1\n");
    CASE("event sign only", "e - 1 1 1 1 1\ne 1 + 1 1 1 1\n");
    CASE("event partial", "e 1 2\ne\ne 3 4 x 6\ne 9 9 9 9 9 9 trailing words\n");
    CASE("event glued", "e1 2 3 4 5 6\ne-1 -2 -3 -4 -5 -6\n");
    CASE("event plus", "e +1 +2 +3 +4 +5 +6\n");
    CASE("event octal looking", "e 010 0x10 3 4 5 6\n");
    CASE("event huge", "e 99999999999 -99999999999 2147483648 -2147483649 4294967296 1\n");
    CASE("ignored lines", " e 1 1 1 1 1 1\nE 1 1 1 1 1 1\nx\n\n\ne 2 2 2 2 2 2\n");
    CASE("crlf", "c 1\r\ne 1 2 3 4 5 6\r\n");
    CASE("nul byte", "c 1\ne 1 2\0 3 4 5 6\ne 7 7 7 7 7 7\n");

    // Lines longer than fgets' 255-byte chunks
    char big[2048];
    int n = 0;
    n += sprintf(big + n, "e 1 2 3 4 5 6");
    memset(big + n, ' ', 250); n += 250;
    n += sprintf(big + n, "e 7 8 9 10 11 12\n");
    loadCase("long line chunked", big, (size_t)n);

    n = 0;
    memset(big, '#', 254); n = 254;
    n += sprintf(big + n, "\ne 1 1 1 1 1 1\n");
    loadCase("255 with newline", big, (size_t)n);

    n = 0;
    n += sprintf(big + n, "e 3 3 3 3 3 3");
    memset(big + n, ' ', 255 - n); n = 255;
    loadCase("exactly 255 no newline", big, (size_t)n);

    n = 0;
    n += sprintf(big + n, "e 4 4 4 4 4 4");
    memset(big + n, ' ', 256 - n); n = 256;
    loadCase("256 no newline", big, (size_t)n);

    // More events than the list holds
    size_t cap = 16384 + 3;
    char *many = malloc(cap*32 + 64);
    size_t m = (size_t)sprintf(many, "c %zu\n", cap);
    for (size_t i = 0; i < cap; i++) m += (size_t)sprintf(many + m, "e %zu 1 2 3 4 5\n", i);
    loadCase("beyond capacity", many, m);
    free(many);

    // Export
    AutomationEventList out = LoadAutomationEventList(NULL);
    AutomationEvent events[] = {
        { 0, 2, { 65, 0, 0, 0 } }, { 5, 7, { -100, 200, 0, 0 } }, { 9, 17, { 1, 2, 3, 4 } },
        { 4000000000u, 0, { -2147483647 - 1, 2147483647, 0, 0 } }, { 12, 21, { 60, 0, 0, 0 } },
    };
    out.count = sizeof(events)/sizeof(events[0]);
    memcpy(out.events, events, sizeof(events));
    printf("export=%d\n", ExportAutomationEventList(out, "out.rae"));
    char *text = LoadFileText("out.rae");
    printf("[%s]\n", text);
    UnloadFileText(text);
    AutomationEventList back = LoadAutomationEventList("out.rae");
    printList("round trip", back);
    UnloadAutomationEventList(back);
    out.count = 0;
    printf("export empty=%d\n", ExportAutomationEventList(out, "empty.rae"));
    text = LoadFileText("empty.rae");
    printf("[%s]\n", text);
    UnloadFileText(text);
    printf("export nodir=%d\n", ExportAutomationEventList(out, "nodir/x.rae"));
    UnloadAutomationEventList(out);

    SetTraceLogCallback(NULL);
    if (chdir("/tmp") != 0) return 2;
    nftw(root, removeEntry, 16, FTW_DEPTH | FTW_PHYS);
    return 0;
}
