#include "CodeSource.h"
#include "CodeObject.h"
#include "CFG.h"
using namespace std;
using namespace Dyninst;
using namespace Dyninst::ParseAPI;

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <binary> [verbose]\nDump the discovered code from the input binary\n", argv[0]);
        exit(-1);
    }

    SymtabCodeSource *sts;
    CodeObject *co;

    sts = new SymtabCodeSource(argv[1]);
    co = new CodeObject(sts);
    co->parse();
}
