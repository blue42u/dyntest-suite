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
  ss << "B[" << std::hex << b.start() << "," << b.end() << ")";
  return ss.str();
}
std::string bstr(const Block* b) {
  if(b == nullptr) return "B(null)";
  return bstr(*b);
}

bool bless(const Block& a, const Block& b) {
  if(a.start() != b.start()) return a.start() < b.start();
  return a.end() < b.end();
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

  std::unordered_set<const Function*> funcs_s;
  for(const Function* func: co->funcs()) funcs_s.emplace(func);

  // Make sure each entry block is only owned by one function.
  std::unordered_map<const Block*, const Function*> entries_s;
  for(const Function* func: co->funcs()) entries_s.emplace(func->entry(), func);

  // Convert the functions into a sorted vector
  std::vector<std::reference_wrapper<const Function>> funcs;
  for(const Function* f: funcs_s) funcs.emplace_back(*f);
  funcs_s.clear();
  std::sort(funcs.begin(), funcs.end(), [](const Function& a, const Function& b){
    return bless(*a.entry(), *b.entry());
  });

  for(const Function& f: funcs) {
    std::cout << "# " << std::hex << f.entry()->start() << std::dec << "\n";

    // Nab all this function's blocks, and all the blocks for the .cold side
    std::unordered_set<const Block*> blocks_s;
    for(const Block* block: f.blocks()) {
      auto it = entries_s.find(block);
      if(it == entries_s.end() || it->second == &f)
        blocks_s.emplace(block);
    }

    // Convert the blocks into a sorted vector
    std::vector<std::reference_wrapper<const Block>> blocks;
    for(const Block* b: blocks_s) blocks.emplace_back(*b);
    blocks_s.clear();
    std::sort(blocks.begin(), blocks.end(), bless);

    // Output the ranges of this function, as compact as possible
    std::pair<std::size_t, std::size_t> cur = {-1,-1};
    for(const Block& b: blocks) {
      if(b.start() != cur.second) {
        if(cur.first != -1) {  // Not the first
          std::cout << "  range [" <<
            std::hex << cur.first << ", " << cur.second << std::dec << ")\n";
        }
        cur = {b.start(), b.end()};
      }
      cur.second = b.end();
    }
    std::cout << "  range [" <<
      std::hex << cur.first << ", " << cur.second << std::dec << ")\n";

    for(const Block& b: blocks) {
      // Gather up all the destinations for this jump table, if there is one.
      std::vector<std::reference_wrapper<const Block>> targets;
      for(const Edge* e: b.targets())
        if(e->type() == EdgeTypeEnum::INDIRECT)
          targets.emplace_back(*e->trg());
      if(targets.empty()) continue;
      for(const Edge* e: b.targets())
        if(e->type() != EdgeTypeEnum::INDIRECT)
          std::cout << "  Malformed jump table on " << bstr(b) << " -> " << bstr(*e->trg()) << "\n";

      // Check for B[-1,-1) targets, they mean something special I think
      bool unbounded = false;
      for(const Block& t: targets) {
        if(t.start() == -1 && t.end() == -1) {
          unbounded = true;
          break;
        }
      }

      // Print out a clean line about this here jump table
      if(unbounded && targets.size() != 1) {
        std::cout << "  Malformed unbounded jump table on " << bstr(b)
          << " with " << (targets.size()-1) << " bounded jumps\n";
      } else if(unbounded) {
        std::cout << "  Unbounded jump table\n";
      } else {
        std::cout << "  Jump table with " << targets.size() << " targets\n";
      }
    }
  }

  return 0;
}
