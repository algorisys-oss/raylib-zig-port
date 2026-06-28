// datacheck.c — validates the Zig rcore's data functions (which the pixel gate
// does not exercise) against published standard test vectors. Linked against the
// Zig raylib library. Exit 0 = all pass.

#include "raylib.h"
#include <stdio.h>
#include <string.h>

static int fails = 0;
#define CHECK(cond, name)                                  \
    do {                                                   \
        if (cond) printf("  PASS  %s\n", name);            \
        else { printf("  FAIL  %s\n", name); fails++; }    \
    } while (0)

int main(void) {
    SetTraceLogLevel(LOG_ERROR);

    // CRC-32 of "123456789" = 0xCBF43926 (the canonical check value)
    unsigned char s1[] = "123456789";
    CHECK(ComputeCRC32(s1, 9) == 0xCBF43926u, "CRC32(\"123456789\")");

    // SHA-1("abc") = a9993e36 4706816a ba3e2571 7850c26c 9cd0d89d
    unsigned char abc[] = "abc";
    unsigned int *sha1 = ComputeSHA1(abc, 3);
    unsigned int e1[5] = {0xa9993e36, 0x4706816a, 0xba3e2571, 0x7850c26c, 0x9cd0d89d};
    CHECK(memcmp(sha1, e1, sizeof e1) == 0, "SHA1(\"abc\")");

    // SHA-256("abc")
    unsigned int *sha256 = ComputeSHA256(abc, 3);
    unsigned int e2[8] = {0xba7816bf, 0x8f01cfea, 0x414140de, 0x5dae2223,
                          0xb00361a3, 0x96177a9c, 0xb410ff61, 0xf20015ad};
    CHECK(memcmp(sha256, e2, sizeof e2) == 0, "SHA256(\"abc\")");

    // Base64: "Man" -> "TWFu", "M" -> "TQ=="
    int olen = 0;
    char *b64 = EncodeDataBase64((const unsigned char *)"Man", 3, &olen);
    CHECK(b64 && strcmp(b64, "TWFu") == 0, "EncodeDataBase64(\"Man\")");

    // Base64 round-trip through DecodeDataBase64
    int dlen = 0;
    unsigned char *dec = DecodeDataBase64((const unsigned char *)"TWFu", &dlen);
    CHECK(dec && dlen == 3 && memcmp(dec, "Man", 3) == 0, "DecodeDataBase64 round-trip");

    // Deflate compress -> decompress round-trip (sdefl/sinfl)
    const char *msg = "the quick brown fox jumps over the lazy dog, the quick brown fox";
    int clen = 0, ulen = 0;
    unsigned char *comp = CompressData((const unsigned char *)msg, (int)strlen(msg), &clen);
    unsigned char *uncomp = DecompressData(comp, clen, &ulen);
    CHECK(uncomp && ulen == (int)strlen(msg) && memcmp(uncomp, msg, ulen) == 0,
          "CompressData/DecompressData round-trip");

    printf("----\n%s (%d failures)\n", fails == 0 ? "OK data functions" : "DATA FAILURES", fails);
    return fails == 0 ? 0 : 1;
}
