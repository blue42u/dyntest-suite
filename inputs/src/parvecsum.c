#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <pthread.h>

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

pthread_mutex_t a_lock;
size_t* a;

size_t n = 1ul << 15;

void* worker(void* _) {
  size_t* b = malloc(n * sizeof *b);
  fill3(b, n);
  pthread_mutex_lock(&a_lock);
  struct timespec zs = {0, 500000000};
  nanosleep(&zs, NULL);
  sum(a, b, n);
  pthread_mutex_unlock(&a_lock);
  free(b);
  return NULL;
}

int main() {
  a = malloc(n * sizeof *a);
  fill2(a, n);
  pthread_mutex_init(&a_lock, NULL);
  pthread_mutex_lock(&a_lock);

  pthread_t
  ts[4];
  for(int i = 0; i < sizeof ts / sizeof ts[0]; i++)
    pthread_create(&ts[i], NULL, worker, NULL);
  pthread_mutex_unlock(&a_lock);
  for(int i = 0; i < sizeof ts / sizeof ts[0]; i++)
    pthread_join(ts[i], NULL);

  pthread_mutex_destroy(&a_lock);
  print(a, n);
  free(a);
  return 0;
}
