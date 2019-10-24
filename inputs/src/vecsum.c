#include <stdlib.h>
#include <stdio.h>

void sum(size_t* restrict a, size_t* restrict b, size_t n) {
  for(size_t i = 0; i < n; i++) {
    for(size_t j = 0; j < n; j++) a[j] += b[j];
    for(size_t j = 0; j < i; j++) a[j] *= b[i];
  }
}

void fill2(size_t* a, size_t n) {
  for(size_t i = 0; i < n; i++)
    a[i] = i*2;
}

void fill3(size_t* a, size_t n) {
  for(size_t i = 0; i < n; i++)
    a[i] = i*3;
}

void print(const size_t* a, size_t n) {
  for(size_t i = 0; i < n; i++)
    printf(" %zu", a[i]);
}

int main() {
  size_t n = 1;
  n <<= 17;
  size_t* a = malloc(n * sizeof *a);
  fill2(a, n);
  size_t* b = malloc(n * sizeof *b);
  fill3(b, n);
  sum(a, b, n);
  print(a, n);
  free(a);
  free(b);
}
