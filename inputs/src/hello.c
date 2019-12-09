#include <stdio.h>
#include <time.h>

void f() {
  printf("f: Hello, world!\n");
  struct timespec zs = {0, 300000000};
  nanosleep(&zs, NULL);
}

void g() {
  printf("g: Hello, world!\n");
  struct timespec zs = {0, 200000000};
  nanosleep(&zs, NULL);
}

int main() {
  printf("main: Hello, world!\n");
  f(); g(); return 0;
}
