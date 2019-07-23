#include <vector>

namespace Dyninst {

namespace ParseAPI {

class Block {};

struct Loop {
  void getLoopBasicBlocks(std::vector<Block *>);
};

struct LoopTreeNode {
  Loop * loop;
};

} // ParseAPI

namespace SymtabAPI {};

} // Dyninst
