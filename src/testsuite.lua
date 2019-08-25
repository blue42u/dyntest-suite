-- luacheck: std lua53, no global

tup.include '../build/build.lua'
function testsuite(o) return build {
  srcdir = 'src/testsuite',
  builddir = o.builddir,
  cfgflags = [[
    -DDyninst_SRC_DIR=src/dyninst
    -DDyninst_ROOT=@]]..o.dyninst..[[@
    -DElfUtils_ROOT_DIR=@]]..o.elfutils..[[@
    -DTBB_ROOT_DIR=@external/tbb@
    -DBoost_ROOT_DIR=@external/boost@
  ]]..(o.cfg or ''),
} end
