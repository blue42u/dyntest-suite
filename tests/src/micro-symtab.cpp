// A simple little microbenchmark

#include <iostream>
#include "Symtab.h"

using namespace Dyninst;
using namespace SymtabAPI;

int main(int argc, const char** argv) {
  if(argc < 2) {
    std::cerr << "Not enough arguments!\n";
    return 2;
  }
  std::cout << "Starting parsing of " << argv[1] << "...\n";

  Symtab* symtab = NULL;
  if(!Symtab::openFile(symtab, argv[1])) {
    std::cerr << "Error opening file!\n";
    return 1;
  }

  Module* defmod = NULL;
  if(!symtab->findModuleByName(defmod, argv[1])) {
    std::cerr << "Unable to find default module!\n";
    return 1;
  }

  symtab->parseTypesNow();
  std::vector<Symbol*> syms;
  symtab->getAllSymbols(syms);

  std::cout << "All done, cleaning up...\n";
  delete symtab;
  return 0;
}
