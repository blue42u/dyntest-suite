-- luacheck: std lua53, no global (Tup-Lua)

local function struct(base, file, out)
  out = out or (file:match '[^/]+$')..'.struct'
  local fn = '../../'..base..'/'..(base == 'inputs' and '' or 'install')..'/'..file
  tup.rule({
    '../../'..base..'/'..(base == 'inputs' and '<bin>' or '<build>'),
    '../../reference/hpctoolkit/<build>',
    '../../reference/elfutils/<build>',
    '../../external/lzma/<build>',
  }, '^o STRUCT %o^ '
    ..'../../reference/hpctoolkit/install/bin/hpcstruct.real -o %o '..fn,
  {out, '<out>'})
end
local function lrstruct(base, file)
  struct('latest/'..base, file, (file:match '[^/]+$')..'.struct')
  struct('reference/'..base, file, (file:match '[^/]+$')..'.ref.struct')
end

-- struct('external/monitor', 'lib/libmonitor.so.0.0.0')
struct('external/tbb', 'lib/libtbbmalloc_proxy.so.2')
struct('external/tbb', 'lib/libtbbmalloc.so.2')
struct('external/tbb', 'lib/libtbb.so.2')
lrstruct('dyninst', 'bin/unstrip')
lrstruct('dyninst', 'lib/libcommon.so.10.1.0')
lrstruct('dyninst', 'lib/libdynDwarf.so.10.1.0')
lrstruct('dyninst', 'lib/libdynElf.so.10.1.0')
lrstruct('dyninst', 'lib/libinstructionAPI.so.10.1.0')
lrstruct('dyninst', 'lib/libparseAPI.so.10.1.0')
lrstruct('dyninst', 'lib/libsymtabAPI.so.10.1.0')
lrstruct('elfutils', 'lib/libdw-0.179.so')
lrstruct('elfutils', 'lib/libelf-0.179.so')
lrstruct('hpctoolkit', 'libexec/hpctoolkit/hpcstruct-bin')
lrstruct('hpctoolkit', 'libexec/hpctoolkit/hpcprof-bin')
struct('latest/hpctoolkit', 'bin/hpcprof2')
-- struct('latest/hpctoolkit', 'libexec/hpctoolkit/hpcprofmock-bin')
lrstruct('hpctoolkit', 'lib/hpctoolkit/libhpcrun.so')
struct('inputs', 'src/fib')
struct('inputs', 'src/hello')
struct('inputs', 'src/parvecsum')
struct('inputs', 'src/ssort')
