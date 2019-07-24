-- luacheck: std lua53, no global

tup.include '../build/build.lua'
function hpctoolkit(o) return build {
  srcdir = 'src/hpctoolkit',
  builddir = o.builddir,
  cfgflags = [[
    --with-boost=@/external/boost@
    --with-tbb=@/external/tbb@
    --with-xerces=@/external/xerces@
    --with-libdwarf=@/external/dwarf@
    --with-binutils=@/external/binutils@
    --with-zlib=@/external/zlib@
    --with-lzma=@/external/lzma@
    --with-xed=@/external/xed@
    --with-libunwind=@/external/unwind@
    --with-papi=@/external/papi@ --with-perfmon=@/external/papi@
    --with-monitor=@/external/monitor@
    --with-elfutils=@]]..o.elfutils..[[@
    --with-dyninst=@]]..o.dyninst..[[@
    --disable-hpcrun-static
  ]]..(o.cfg or ''),
} end
