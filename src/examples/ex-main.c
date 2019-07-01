extern void print();

int main(int argc, char **argv) {
  print();
  return 0;
}

int f(int x) {
  static int y = 5;
  if(y == 6) return x;
  return 0;
}
