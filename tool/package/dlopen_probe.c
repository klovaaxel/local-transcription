/* Minimal dlopen probe used by the packaging checks: does this .so actually
 * load, with whatever loader path the caller set up? The local brief is an FFI
 * dlopen of libllama.so, so this is the thing that has to succeed. */
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: dlopen_probe <library>\n"); return 2; }
  void *h = dlopen(argv[1], RTLD_NOW);
  if (!h) { printf("dlopen FAILED: %s\n", dlerror()); return 1; }
  printf("dlopen OK\n");
  dlclose(h);
  return 0;
}
