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

  // Mark down the entries
  std::unordered_map<const Block*, std::reference_wrapper<const Function>> entries;
  for(const Function* f: funcs_s) entries.emplace(f->entry(), *f);

  // Look up the mangled names for everything, and remove any .cold blobs.
  auto symtab = source->getSymtabObject();
  std::unordered_map<const Function*, bool> frozen;
  for(const Function* f: funcs_s) {
    bool cold = false;
    for(const auto& sym: symtab->findSymbolByOffset(f->entry()->start())) {
      if(sym->getMangledName().find(".cold") != std::string::npos) {
        cold = true;
        break;
      }
    }
    frozen.emplace(f, cold);
  }

  // Convert the functions into a sorted vector
  std::vector<std::reference_wrapper<const Function>> funcs;
  for(const Function* f: funcs_s) funcs.emplace_back(*f);
  funcs_s.clear();
  std::sort(funcs.begin(), funcs.end(), [](const Function& a, const Function& b){
    return bless(*a.entry(), *b.entry());
  });

  for(const Function& f: funcs) {
    // Check that this isn't a cold blob.
    if(frozen.at(&f)) continue;

    std::cout << "# " << std::hex << f.entry()->start() << std::dec << "\n";

    // Nab all this function's blocks, and all the blocks for the .cold side
    std::unordered_set<const Block*> blocks_s;
    for(const Block* block: f.blocks()) {
      // If the only outgoing edge from this block is an "interprocedural"
      // fallthough edge, elide it.
      if(block->targets().size() == 1 && (*block->targets().begin())->interproc()
         && (*block->targets().begin())->type() == FALLTHROUGH)
        continue;

      // If there's an outgoing edge to a frozen entry, pull in all its blocks
      for(const Edge* e : block->targets()) {
        auto it = entries.find(e->trg());
        if(it == entries.end()) continue;
        const Function& ef = it->second;
        if(frozen.at(&ef))
          for(const Block* b : ef.blocks())
            blocks_s.emplace(b);
      }

      blocks_s.emplace(block);
    }

    // Convert the blocks into a sorted vector
    std::vector<std::reference_wrapper<const Block>> blocks;
    for(const Block* b: blocks_s) blocks.emplace_back(*b);
    blocks_s.clear();
    std::sort(blocks.begin(), blocks.end(), bless);

    // Output the ranges of this function, as compact as possible
    auto fname = f.name();
    bool cold = fname.size() > 5 && fname.substr(fname.size()-5) == ".cold";
    std::pair<std::size_t, std::size_t> cur = {-1,-1};
    for(const Block& b: blocks) {
      if(b.start() != cur.second) {
        if(cur.first != -1) {  // Not the first
          if(cold) break;  // Only one range for cold blobs
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
