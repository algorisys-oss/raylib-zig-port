// core_files.c — C-vs-Zig differential for rcore's hash and path functions.
//
// SHA256/SHA1/MD5 for every input length 0..200 (all padding boundaries, incl.
// 6.2's SHA256 padding fix at n%64 in 52..55), and GetPrevDirectoryPath/
// IsFileHidden/IsPathAbsolute/IsPathFile/IsPathDirectory/GetDirectoryPath/
// GetFileNameWithoutExt over tricky paths (roots, trailing separators, dot
// entries, Windows-style strings on POSIX). Run via tools/cdiff.sh.
#include <stdio.h>
#include <string.h>
#include "raylib.h"
int main(void){
    SetTraceLogLevel(LOG_NONE);
    static unsigned char buf[300];
    for (int i=0;i<300;i++) buf[i]=(unsigned char)(i*37+11);
    for (int n=0;n<=200;n++){
        unsigned int *h=ComputeSHA256(buf,n); printf("256 %d",n); for(int k=0;k<8;k++)printf(" %08x",h[k]); printf("\n");
        h=ComputeSHA1(buf,n); printf("1 %d",n); for(int k=0;k<5;k++)printf(" %08x",h[k]); printf("\n");
        h=ComputeMD5(buf,n); printf("md5 %d",n); for(int k=0;k<4;k++)printf(" %08x",h[k]); printf("\n");
    }
    const char *paths[]={"","/","//","/usr","/usr/","/usr/bin","/usr/bin/","/etc/hostname","/etc/hostname/","a","a/","a/b","a/b/c",
      "C:\\","C:\\raylib","C:\\raylib\\","C:\\raylib\\src","./x","../","..","/tmp","/tmp/","/proc/self/status","x/y/z/",
      ".hidden","dir/.hidden","/a/.","/a/..",".","..","a.b/.c","/nonexist/file.txt","\\\\server\\share",NULL};
    for (int i=0;paths[i];i++){
        printf("[%s] prev=[%s] hid=%d abs=%d file=%d dir=%d dirpath=[%s] noext=[%s]\n",paths[i],GetPrevDirectoryPath(paths[i]),
          IsFileHidden(paths[i]),IsPathAbsolute(paths[i]),IsPathFile(paths[i]),IsPathDirectory(paths[i]),GetDirectoryPath(paths[i]),GetFileNameWithoutExt(paths[i]));
    }
    printf("absnull=%d\n", IsPathAbsolute(NULL));
    return 0;
}
