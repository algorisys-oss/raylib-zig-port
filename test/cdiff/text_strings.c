// text_strings.c — C-vs-Zig differential for rtext's string functions.
//
// Edge-case battery (empty, leading/trailing/doubled '_', acronyms, negative
// and past-the-end positions/lengths, over-length split) through TextToPascal/
// Camel/Snake, TextInsert(Alloc), TextSubtext, TextReplace(Alloc),
// GetTextBetween, TextSplit, LoadTextLines, TextJoin. No example drives these
// inputs, so the examples gate can't see them. Run via tools/cdiff.sh.
#include <stdio.h>
#include <stdlib.h>
#include "raylib.h"
static const char *S[] = {"", "a", "_", "__", "a_", "hello_world", "hello__world_", "_lead", "my_1st_var", "x_é_y",
 "HTTPRequest", "helloWorld", "Hello World", "  spaced  out ", "ABC", "aB", "AbC dEf", "already_snake", "MyHTTPServer2Go",
 "A", "Foo  Bar", "foo_Bar", "XMLHttpRequest", "a1B2", "trail ", 0};
int main(void){
  for (int k=0;S[k];k++){
    printf("[%s] P=[%s]", S[k], TextToPascal(S[k]));
    printf(" C=[%s]", TextToCamel(S[k]));
    printf(" S=[%s]\n", TextToSnake(S[k]));
    for (int p=-2;p<20;p+=3){ printf(" I%d=[%s]", p, TextInsert(S[k],"<>",p)); char *a=TextInsertAlloc(S[k],"<>",p); printf("[%s]", a?a:"NULL"); free(a);
      for (int l=-1;l<6;l+=2) printf(" U%d,%d=[%s]",p,l,TextSubtext(S[k],p,l)); }
    printf("\n R=[%s]", TextReplace(S[k],"_","--")); char *r=TextReplaceAlloc(S[k],"o","0"); printf("[%s]", r?r:"NULL"); free(r);
    printf(" B=[%s]\n", GetTextBetween(S[k],"_","_"));
    int c; char **sp = TextSplit(S[k], '_', &c); printf(" N=%d", c); for(int i=0;i<c;i++) printf("{%s}", sp[i]); printf("\n");
    int lc; char **ln = LoadTextLines("ab\ncd\n\nefg", &lc); for(int i=0;i<lc;i++) printf("<%s>", ln[i]); UnloadTextLines(ln, lc); printf("\n");
  }
  const char *L[] = {"aaa","bbbb","cc"}; printf("J=[%s]\n", TextJoin((char**)L,3,", "));
  static char big[1100]; for(int i=0;i<1099;i++) big[i]='a'+i%26; big[1099]=0;
  printf("SPLIT big: "); int c; char **sp=TextSplit(big,'z',&c); printf("%d %zu\n", c, (size_t)TextLength(sp[c-1]));
  printf("BETWEEN big: %zu\n", (size_t)TextLength(GetTextBetween("[", "[", "]")));
  return 0;
}
