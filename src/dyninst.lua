-- luacheck: std lua53, no global

tup.include '../build/build.lua'
function dyninst(o) return build {
  srcdir = 'src/'..(o.ref and 'ref-' or '')..'dyninst',
  builddir = o.builddir,
  cfgflags = [[
    -DBoost_ROOT_DIR=@/external/boost@
    -DTBB_ROOT_DIR=@/external/tbb@
    -DElfUtils_ROOT_DIR=@]]..o.elfutils..[[@
  ]]..(o.cfg or ''),
} end
