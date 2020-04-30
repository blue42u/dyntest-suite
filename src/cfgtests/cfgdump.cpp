#include <CodeSource.h>
#include <CodeObject.h>

#include <iostream>
#include <memory>
#include <cstring>
#include <algorithm>
#include <unordered_map>
#include <unordered_set>
#include <sstream>

using namespace Dyninst::ParseAPI;

std::string bstr(const Block& b) {
  std::ostringstream ss;
  ss << "B[" << std::hex << b.start() << "," << b.end() << "]";
  return ss.str();
}
std::string bstr(const Block* b) {
  if(b == nullptr) return "B(null)";
  return bstr(*b);
}

std::string etstr(EdgeTypeEnum et) {
  switch(et) {
  case EdgeTypeEnum::CALL: return "call";
  case EdgeTypeEnum::COND_TAKEN: return "if true";
  case EdgeTypeEnum::COND_NOT_TAKEN: return "if false";
  case EdgeTypeEnum::INDIRECT: return "indirect";
  case EdgeTypeEnum::DIRECT: return "always";
  case EdgeTypeEnum::FALLTHROUGH: return "fallthrough";
  case EdgeTypeEnum::CATCH: return "catch";
  case EdgeTypeEnum::CALL_FT: return "after call";
  case EdgeTypeEnum::RET: return "return";
  default: return "unknown";
  }
}

int main(int argc, const char** argv) {
  if(argc != 2) {
    std::cerr << "Usage: " << (argc > 0 ? argv[0] : "$0") << " path/to/binary\n";
    return 1;
  }

  auto source = std::make_unique<SymtabCodeSource>((char*)argv[1]);
  auto co = std::make_unique<CodeObject>(source.get());

  co->parse();

  std::unordered_set<const Block*> blocks_set;
  for(const Function* func: co->funcs())
    for(const Block* block: func->blocks())
      blocks_set.emplace(block);

  std::vector<std::reference_wrapper<const Block>> blocks;
  for(const Block* block: blocks_set) blocks.emplace_back(*block);
  std::sort(blocks.begin(), blocks.end(), [](const Block& a, const Block& b){
    if(a.start() != b.start()) return a.start() < b.start();
    return a.end() < b.end();
  });

  for(const Block& b: blocks) {
    std::cout << "# " << bstr(b) << "\n";
    std::vector<std::reference_wrapper<const Edge>> edges;
    for(const Edge* e: b.targets()) edges.emplace_back(*e);
    std::sort(edges.begin(), edges.end(), [](const Edge& a, const Edge& b){
      if(a.trg()->start() != b.trg()->start()) return a.trg()->start() < b.trg()->start();
      if(a.trg()->end() != b.trg()->end()) return a.trg()->end() < b.trg()->end();
      return a.type() < b.type();
    });
    for(const Edge& e: edges)
      std::cout << "  % -(" << etstr(e.type()) << ")> " << bstr(e.trg()) << "\n";
  }

  return 0;
}
