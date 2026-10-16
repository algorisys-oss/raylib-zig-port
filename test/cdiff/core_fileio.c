// core_fileio.c — C-vs-Zig differential for rcore's file system functions.
//
// Drives every file I/O, path and directory function against a real file tree
// in a fresh temp directory: success and failure paths, filters, recursion,
// the user I/O callbacks, and every TraceLog line (captured through a log
// callback, so warnings are compared as well as results). All paths printed
// are relative to the temp directory, so the C and Zig runs print the same
// text. Run via tools/cdiff.sh.
#define _XOPEN_SOURCE 700
#include <ftw.h>
#include <libgen.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "raylib.h"

static void logCallback(int level, const char *text, va_list args)
{
    printf("  log %d: ", level);
    vprintf(text, args);
    printf("\n");
}

static void printBytes(const char *what, const unsigned char *data, int size)
{
    unsigned int sum = 0;
    for (int i = 0; i < size; i++) sum = sum*31 + data[i];
    printf("%s: %s size=%d sum=%08x\n", what, data ? "data" : "NULL", size, sum);
}

static void printText(const char *what, const char *text)
{
    if (text) printf("%s: [%s]\n", what, text);
    else printf("%s: NULL\n", what);
}

static void printList(const char *what, FilePathList list)
{
    printf("%s: count=%u\n", what, list.count);
    for (unsigned int i = 0; i < list.count; i++) printf("  [%s]\n", list.paths[i]);
}

static unsigned char *customLoadData(const char *fileName, int *dataSize)
{
    printf("customLoadData(%s)\n", fileName);
    *dataSize = 3;
    unsigned char *data = MemAlloc(3);
    data[0] = 1; data[1] = 2; data[2] = 3;
    return data;
}
static bool customSaveData(const char *fileName, const void *data, int dataSize)
{
    printf("customSaveData(%s, %d)\n", fileName, dataSize);
    (void)data;
    return false;
}
static char *customLoadText(const char *fileName)
{
    printf("customLoadText(%s)\n", fileName);
    char *text = MemAlloc(4);
    strcpy(text, "abc");
    return text;
}
static bool customSaveText(const char *fileName, const char *text)
{
    printf("customSaveText(%s, %s)\n", fileName, text);
    return true;
}

static int removeEntry(const char *path, const struct stat *st, int flag, struct FTW *ftw)
{
    (void)st; (void)flag; (void)ftw;
    return remove(path);
}

int main(void)
{
    char root[] = "/tmp/rlfileio_XXXXXX";
    if (!mkdtemp(root) || chdir(root) != 0) return 2;

    SetTraceLogLevel(LOG_ALL);
    SetTraceLogCallback(logCallback);

    unsigned char bytes[300];
    for (int i = 0; i < 300; i++) bytes[i] = (unsigned char)(i*37 + 11);

    // Binary data
    printf("save a.bin=%d\n", SaveFileData("a.bin", bytes, 300));
    printf("save empty.bin=%d\n", SaveFileData("empty.bin", bytes, 0));
    printf("save nodir=%d\n", SaveFileData("nodir/a.bin", bytes, 10));
    printf("save null=%d\n", SaveFileData(NULL, bytes, 10));

    int size = -1;
    unsigned char *data = LoadFileData("a.bin", &size);
    printBytes("load a.bin", data, size);
    UnloadFileData(data);
    data = LoadFileData("empty.bin", &size);
    printBytes("load empty.bin", data, size);
    data = LoadFileData("missing.bin", &size);
    printBytes("load missing", data, size);
    data = LoadFileData(NULL, &size);
    printBytes("load null", data, size);

    // Text
    printf("save t.txt=%d\n", SaveFileText("t.txt", "hello\nworld, hello\n"));
    printf("save e.txt=%d\n", SaveFileText("e.txt", ""));
    printf("save nodir=%d\n", SaveFileText("nodir/t.txt", "x"));
    printf("save null=%d\n", SaveFileText(NULL, "x"));
    char *text = LoadFileText("t.txt");
    printText("load t.txt", text);
    UnloadFileText(text);
    printText("load e.txt", LoadFileText("e.txt"));
    printText("load missing", LoadFileText("missing.txt"));
    printText("load null", LoadFileText(NULL));

    // Data as code
    printf("export my-data.v1.h=%d\n", ExportDataAsCode(bytes, 45, "my-data.v1.h"));
    text = LoadFileText("my-data.v1.h");
    printText("my-data.v1.h", text);
    UnloadFileText(text);
    printf("export one.h=%d\n", ExportDataAsCode(bytes, 1, "dir.x/one?!+.h"));
    printf("export one.h=%d\n", ExportDataAsCode(bytes, 1, "one?!+.h"));
    text = LoadFileText("one?!+.h");
    printText("one?!+.h", text);
    UnloadFileText(text);

    // Queries
    const char *names[] = { "a.bin", "empty.bin", "missing.bin", ".", "t.txt", NULL };
    for (int i = 0; names[i]; i++) {
        struct stat st = { 0 };
        int statOk = stat(names[i], &st) == 0;
        printf("[%s] exists=%d dir=%d len=%d mtimeok=%d isfile=%d isdir=%d\n", names[i], FileExists(names[i]),
            DirectoryExists(names[i]), GetFileLength(names[i]), GetFileModTime(names[i]) == (statOk ? (long)st.st_mtime : 0),
            IsPathFile(names[i]), IsPathDirectory(names[i]));
    }
    printf("exists null=%d\n", FileExists(NULL));

    const char *extCases[][2] = {
        { "a.PNG", ".png" }, { "a.png", ".PNG" }, { "a.png", "png" }, { "a.jpg", ".png;.jpg" },
        { "a.jpg", ".png;jpg;.bmp" }, { "a.bmp", ".png;.jpg" }, { "noext", ".png" }, { ".bashrc", ".bashrc" },
        { "dir.d/file", ".d/file" }, { "a.tar.gz", ".gz" }, { "a.tar.gz", ".tar.gz" },
        { "a.verylongextension_x", ".verylongextension_x" }, { "a.verylongexten", ".verylongexten" },
        { "a.png", "" }, { "a.png", ";" }, { "a.png", ".png;" }, { NULL, NULL },
    };
    for (int i = 0; extCases[i][0]; i++) {
        printf("ext [%s] [%s] = %d\n", extCases[i][0], extCases[i][1], IsFileExtension(extCases[i][0], extCases[i][1]));
    }

    const char *pathCases[] = { "a.b.c", ".hidden", "noext", "dir.d/file", "a/b/c.txt", "c.txt", "a\\b.txt", "a/",
        "", "/", "x/.y", "a.b/c.d.e", NULL };
    for (int i = 0; pathCases[i]; i++) {
        const char *ext = GetFileExtension(pathCases[i]);
        printf("path [%s] ext=[%s] name=[%s]", pathCases[i], ext ? ext : "(null)", GetFileName(pathCases[i]));
        printf(" noext=[%s]\n", GetFileNameWithoutExt(pathCases[i]));
    }

    const char *validCases[] = { "ok.txt", "", "a<b", "a:b", "a\"b", "a/b", "a\\b", "a|b", "a?b", "a*b", "\x01x", ".", "..",
        "...", ".a", "a.", NULL };
    for (int i = 0; validCases[i]; i++) printf("valid [%s] = %d\n", validCases[i], IsFileNameValid(validCases[i]));
    printf("valid null=%d\n", IsFileNameValid(NULL));

    // Directories
    printf("mkdir x/y/z=%d\n", MakeDirectory("x/y/z"));
    printf("mkdir x/y/z again=%d\n", MakeDirectory("x/y/z"));
    printf("mkdir w\\v=%d\n", MakeDirectory("w\\v"));
    printf("mkdir empty=%d\n", MakeDirectory(""));
    printf("mkdir null=%d\n", MakeDirectory(NULL));
    printf("mkdir under file=%d\n", MakeDirectory("a.bin/sub"));
    printf("dirs x=%d x/y/z=%d w/v=%d\n", DirectoryExists("x"), DirectoryExists("x/y/z"), DirectoryExists("w/v"));

    // Copy, move, rename, remove
    printf("copy=%d\n", FileCopy("a.bin", "c1/c2/copy.bin"));
    printf("copy missing=%d\n", FileCopy("missing.bin", "c1/missing.bin"));
    printf("copy empty=%d\n", FileCopy("empty.bin", "c1/empty.bin"));
    printBytes("copied", data = LoadFileData("c1/c2/copy.bin", &size), size);
    UnloadFileData(data);
    printf("move=%d\n", FileMove("c1/c2/copy.bin", "m1/moved.bin"));
    printf("move missing=%d\n", FileMove("missing.bin", "m1/x.bin"));
    printf("after move src=%d dst=%d\n", FileExists("c1/c2/copy.bin"), FileExists("m1/moved.bin"));
    printf("rename=%d\n", FileRename("m1/moved.bin", "m1/renamed.bin"));
    printf("rename missing=%d\n", FileRename("missing.bin", "m1/y.bin"));
    printf("remove=%d\n", FileRemove("m1/renamed.bin"));
    printf("remove missing=%d\n", FileRemove("m1/renamed.bin"));

    // Text search and replace
    printf("find hello=%d\n", FileTextFindIndex("t.txt", "hello"));
    printf("find world=%d\n", FileTextFindIndex("t.txt", "world"));
    printf("find none=%d\n", FileTextFindIndex("t.txt", "zzz"));
    printf("find missing=%d\n", FileTextFindIndex("missing.txt", "x"));
    printf("replace=%d\n", FileTextReplace("t.txt", "hello", "bye"));
    printf("replace missing=%d\n", FileTextReplace("missing.txt", "a", "b"));
    text = LoadFileText("t.txt");
    printText("replaced", text);
    UnloadFileText(text);

    // Directory scans
    SaveFileText("x/one.txt", "1");
    SaveFileText("x/y/two.TXT", "2");
    SaveFileText("x/y/z/three.png", "3");
    SaveFileText("x/.hidden", "h");
    const char *filters[] = { "*.*", "FILES*", "DIRS*", ".txt", ".png;.txt", ".h", "", "FILES*;DIRS*", NULL };
    for (int i = 0; filters[i]; i++) {
        for (int sub = 0; sub <= 1; sub++) {
            char what[64];
            snprintf(what, sizeof(what), "scan . [%s] sub=%d count=%u", filters[i], sub, GetDirectoryFileCountEx(".", filters[i], sub));
            FilePathList list = LoadDirectoryFilesEx(".", filters[i], sub);
            printList(what, list);
            UnloadDirectoryFiles(list);
        }
    }
    FilePathList list = LoadDirectoryFilesEx(".", NULL, true);
    printList("scan . null sub=1", list);
    UnloadDirectoryFiles(list);
    list = LoadDirectoryFiles("x");
    printList("LoadDirectoryFiles x", list);
    UnloadDirectoryFiles(list);
    printf("count x=%u\n", GetDirectoryFileCount("x"));
    list = LoadDirectoryFiles("missing");
    printList("LoadDirectoryFiles missing", list);
    UnloadDirectoryFiles(list);
    printf("count missing=%u\n", GetDirectoryFileCount("missing"));
    list = LoadDirectoryFilesEx("x/", "*.*", true);
    printList("scan x/ sub=1", list);
    UnloadDirectoryFiles(list);

    // Working and application directory
    char cwd[4096];
    printf("cwd ok=%d\n", strcmp(GetWorkingDirectory(), getcwd(cwd, sizeof(cwd))) == 0);
    printf("chdir x=%d\n", ChangeDirectory("x"));
    printf("cwd x ok=%d\n", strcmp(GetWorkingDirectory(), getcwd(cwd, sizeof(cwd))) == 0);
    printf("chdir ..=%d\n", ChangeDirectory(".."));
    printf("chdir missing=%d\n", ChangeDirectory("missing"));
    char exe[4096] = { 0 };
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n > 0) exe[n] = 0;
    char appDir[4096];
    snprintf(appDir, sizeof(appDir), "%s/", dirname(exe));
    printf("appdir ok=%d\n", strcmp(GetApplicationDirectory(), appDir) == 0);

    // User I/O callbacks take over the whole call
    SetLoadFileDataCallback(customLoadData);
    SetSaveFileDataCallback(customSaveData);
    SetLoadFileTextCallback(customLoadText);
    SetSaveFileTextCallback(customSaveText);
    data = LoadFileData("cb.bin", &size);
    printBytes("cb load", data, size);
    MemFree(data);
    printf("cb save=%d\n", SaveFileData("cb.bin", bytes, 5));
    text = LoadFileText("cb.txt");
    printText("cb load text", text);
    MemFree(text);
    printf("cb save text=%d\n", SaveFileText("cb.txt", "zz"));
    printf("cb exists=%d\n", FileExists("cb.bin"));
    SetLoadFileDataCallback(NULL);
    SetSaveFileDataCallback(NULL);
    SetLoadFileTextCallback(NULL);
    SetSaveFileTextCallback(NULL);

    SetTraceLogCallback(NULL);
    if (chdir("/tmp") != 0) return 2;
    nftw(root, removeEntry, 16, FTW_DEPTH | FTW_PHYS);
    return 0;
}
