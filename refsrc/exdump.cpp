//
//  Copyright (c) 2017, Rice University.
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are
//  met:
//
//  * Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//
//  * Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
//  * Neither the name of Rice University (RICE) nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
//  This software is provided by RICE and contributors "as is" and any
//  express or implied warranties, including, but not limited to, the
//  implied warranties of merchantability and fitness for a particular
//  purpose are disclaimed. In no event shall RICE or contributors be
//  liable for any direct, indirect, incidental, special, exemplary, or
//  consequential damages (including, but not limited to, procurement of
//  substitute goods or services; loss of use, data, or profits; or
//  business interruption) however caused and on any theory of liability,
//  whether in contract, strict liability, or tort (including negligence
//  or otherwise) arising in any way out of the use of this software, even
//  if advised of the possibility of such damage.
//
// ----------------------------------------------------------------------
//
//  This program is a proxy for hpcstruct with threads.
//
//  Iterate through the same hierarchy of functions, loops, blocks,
//  instructions, inline call sequences and line map info, and collect
//  (mostly) the same raw data that hpcstruct would collect.  But
//  don't build a full inline tree, instead just collect summary info
//  for each function.
//
//  This program tests that ParseAPI and SymtabAPI can be run in
//  parallel.  For now, we parse the entire binary sequentially (unless
//  ParseAPI is built with threads) and then make parallel queries.
//
//  Build me as:
//  ./mk-dyninst.sh  cilk-parse.cpp  externals-dir
//
//  Usage:
//  ./cilk-parse  [options]...  filename  [ num-threads ]
//
//  Options:
//   -I, -Iall    do not split basic blocks into instructions
//   -Iinline     do not compute inline callsite sequences
//   -Iline       do not compute line map info
//   -q           don't acutally print anything
//

#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

#include <iostream>
#include <map>
#include <string>
#include <utility>
#include <vector>
#include <mutex>

#include <CFG.h>
#include <CodeObject.h>
#include <CodeSource.h>
#include <Function.h>
#include <Symtab.h>
#include <Instruction.h>
#include <LineInformation.h>

#include <omp.h>

#define MAX_VMA  0xfffffffffffffff0
#define DEFAULT_THREADS  4

using namespace Dyninst;
using namespace ParseAPI;
using namespace SymtabAPI;
using namespace InstructionAPI;
using namespace std;

typedef map <Block *, bool> BlockSet;
typedef unsigned int uint;

Symtab * the_symtab = NULL;

// Command-line options
class Options {
public:
    const char *filename;
    int   num_threads;
    bool  do_instns;
    bool  do_inline;
    bool  do_linemap;
    bool  do_prints;

    Options() {
	filename = NULL;
	num_threads = 0;
	do_instns = true;
	do_inline = true;
	do_linemap = true;
        do_prints = true;
    }
};

Options opts;

//----------------------------------------------------------------------

// Summary info for each function.
//
// Just enough to prove that we've walked through the hierarchy of
// loops, blocks and instructions, but without creating our own inline
// tree info.
//
class FuncInfo {
public:
    string  name;
    Offset  addr;
    Offset  min_vma;
    Offset  max_vma;
    int  num_loops;
    int  num_blocks;
    int  num_instns;
    int  max_depth;
    int  min_line;
    int  max_line;

    FuncInfo(ParseAPI::Function * func) {
	name = func->name();
	addr = func->addr();
	min_vma = MAX_VMA;
	max_vma = 0;
	num_loops = 0;
	num_blocks = 0;
	num_instns = 0;
	max_depth = 0;
	min_line = 0;
	max_line = 0;
    }
};

//----------------------------------------------------------------------

void
doInstruction(Offset addr, FuncInfo & finfo)
{
    finfo.num_instns++;

    // line map info (optional)
    if (opts.do_linemap) {
	SymtabAPI::Function * sym_func = NULL;
	Module * mod = NULL;
	vector <Statement::Ptr> svec;

	the_symtab->getContainingFunction(addr, sym_func);
	if (sym_func != NULL) {
	    mod = sym_func->getModule();
	}
	if (mod != NULL) {
	    mod->getSourceLines(svec, addr);
	}

	if (! svec.empty()) {
	    int line = svec[0]->getLine();

	    // line = 0 means unknown
	    if (line > 0) {
		if (line < finfo.min_line || finfo.min_line == 0) {
		    finfo.min_line = line;
		}
		finfo.max_line = std::max(finfo.max_line, line);
	    }
	}
    }

    // inline call sequence (optional)
    if (opts.do_inline) {
	FunctionBase *func, *parent;
	int depth = 0;

	if (the_symtab->getContainingInlinedFunction(addr, func) && func != NULL)
	{
	    parent = func->getInlinedParent();
	    while (parent != NULL) {
		//
		// func is inlined iff it has a parent
		//
		InlinedFunction *ifunc = static_cast <InlinedFunction *> (func);
		pair <string, Offset> callsite = ifunc->getCallsite();

		depth++;

		func = parent;
		parent = func->getInlinedParent();
	    }
	}
	finfo.max_depth = std::max(finfo.max_depth, depth);
    }
}

//----------------------------------------------------------------------

void
doBlock(Block * block, BlockSet & visited, FuncInfo & finfo)
{
    if (visited[block]) {
	return;
    }
    visited[block] = true;

    finfo.num_blocks++;
    finfo.min_vma = std::min(finfo.min_vma, block->start());
    finfo.max_vma = std::max(finfo.max_vma, block->end());

    // split basic block into instructions (optional)
    if (opts.do_instns) {
	map <Offset, boost::shared_ptr<Instruction>> imap;
	block->getInsns(imap);

	for (auto iit = imap.begin(); iit != imap.end(); ++iit) {
	    Offset addr = iit->first;
	    doInstruction(addr, finfo);
	}
    }
}

//----------------------------------------------------------------------

void
doLoop(Loop * loop, BlockSet & visited, FuncInfo & finfo)
{
    finfo.num_loops++;

    // blocks in this loop
    vector <Block *> blist;
    loop->getLoopBasicBlocks(blist);

    for (uint i = 0; i < blist.size(); i++) {
	Block * block = blist[i];

	doBlock(block, visited, finfo);
    }
}

//----------------------------------------------------------------------

void
doLoopTree(LoopTreeNode * ltnode, BlockSet & visited, FuncInfo & finfo)
{
    // recur on subloops first
    vector <LoopTreeNode *> clist = ltnode->children;

    for (uint i = 0; i < clist.size(); i++) {
	doLoopTree(clist[i], visited, finfo);
    }

    // this loop last, in post order
    Loop *loop = ltnode->loop;
    doLoop(loop, visited, finfo);
}

//----------------------------------------------------------------------

void
doFunction(ParseAPI::Function * func)
{
    FuncInfo finfo(func);

    // map of visited blocks
    const ParseAPI::Function::blocklist & blist = func->blocks();
    BlockSet visited;

    for (auto bit = blist.begin(); bit != blist.end(); ++bit) {
	Block * block = *bit;
	visited[block] = false;
    }

    LoopTreeNode * ltnode = func->getLoopTree();
    vector <LoopTreeNode *> clist = ltnode->children;

    // there is no top-level loop, only subtrees
    for (uint i = 0; i < clist.size(); i++) {
	doLoopTree(clist[i], visited, finfo);
    }

    // blocks not in any loop
    for (auto bit = blist.begin(); bit != blist.end(); ++bit) {
	Block * block = *bit;

	if (! visited[block]) {
	    doBlock(block, visited, finfo);
	}
    }

    // print info for this function
    if(opts.do_prints)
        #pragma omp ordered
        cout << "\n--------------------------------------------------\n"
	     << hex
	     << "func:  0x" << finfo.addr << "  " << finfo.name << "\n"
	     << "0x" << finfo.min_vma << "--0x" << finfo.max_vma << "\n"
	     << dec
	     << "loops:  " << finfo.num_loops
	     << "  blocks:  " << finfo.num_blocks
	     << "  instns:  " << finfo.num_instns << "\n"
	     << "inline depth:  " << finfo.max_depth
	     << "  line range:  " << finfo.min_line << "--" << finfo.max_line
	     << "\n";
}

//----------------------------------------------------------------------

const std::string usageMessage = 
    "usage: cilk-parse [options]... filename [num-threads]\n\n"
    "options:\n"
    "  -I, -Iall    do not split basic blocks into instructions\n"
    "  -Iinline     do not compute inline callsite sequences\n"
    "  -Iline       do not compute line map info\n"
    "  -q           don't actually print anything\n"
    "\n";

void
getOptions(int argc, char **argv, Options & opts)
{
    if (argc < 2) {
        cerr << usageMessage;
        exit(1);
    }

    int n = 1;
    while (n < argc) {
	string arg(argv[n]);

	if (arg == "-I" || arg == "-Iall") {
	    opts.do_instns = false;
	    n++;
	}
	else if (arg == "-Iinline") {
	    opts.do_inline = false;
	    n++;
	}
	else if (arg == "-Iline") {
	    opts.do_linemap = false;
	    n++;
	}
        else if (arg == "-q") {
            opts.do_prints = false;
            n++;
        }
	else if (arg[0] == '-') {
	    cerr << "invalid option: " << arg << "\n" << usageMessage;
            exit(1);
	}
	else {
	    break;
	}
    }

    // filename (required)
    if (n < argc) {
	opts.filename = argv[n];
    }
    else {
	cerr << "missing file name\n" << usageMessage;
    }
    n++;

    // num threads (optional)
    if (n < argc) {
	opts.num_threads = atoi(argv[n]);
    }
    else {
	opts.num_threads = DEFAULT_THREADS;
    }
    if (opts.num_threads <= 0) {
        cerr << "bad argument for num_threads\n" << usageMessage;
        exit(1);
    }
}

//----------------------------------------------------------------------

int
main(int argc, char **argv)
{
    getOptions(argc, argv, opts);
    omp_set_num_threads(opts.num_threads);

    if (! Symtab::openFile(the_symtab, opts.filename)) {
	errx(1, "Symtab::openFile failed: %s", opts.filename);
    }
    the_symtab->parseTypesNow();
    the_symtab->parseFunctionRanges();

    vector <Module *> modVec;
    the_symtab->getAllModules(modVec);

    for (auto mit = modVec.begin(); mit != modVec.end(); ++mit) {
	(*mit)->parseLineInformation();
    }

    SymtabCodeSource * code_src = new SymtabCodeSource(the_symtab);
    CodeObject * code_obj = new CodeObject(code_src);
    code_obj->parse();

    // get function list and convert to vector. parallel for requires a
    // random access container.

    const CodeObject::funclist & funcList = code_obj->funcs();
    vector <ParseAPI::Function *> funcVec;

    for (auto fit = funcList.begin(); fit != funcList.end(); ++fit) {
	ParseAPI::Function * func = *fit;
	funcVec.push_back(func);
    }

#pragma omp parallel for schedule(static,1) ordered
    for (size_t n = 0; n < funcVec.size(); n++) {
	ParseAPI::Function * func = funcVec[n];
	doFunction(func);
    }

    if(opts.do_prints)
        cout << "\ndone parsing: " << opts.filename << "\n"
	     << "  num funcs: " << funcVec.size() << "\n\n";

    return 0;
}
