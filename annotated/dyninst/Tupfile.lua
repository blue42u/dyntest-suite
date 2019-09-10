-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/dyninst.lua'
dyninst {
  builddir = 'annotated/dyninst',
  elfutils = '../elfutils',
  cfg = [[
    -DADD_VALGRIND_ANNOTATIONS=ON
    -DValgrind_ROOT_DIR=@/external/valgrind@
  ]]..ompcfg,
}
