-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/hpctoolkit.lua'
hpctoolkit {
  builddir = 'annotated/hpctoolkit',
  elfutils = '../elfutils',
  dyninst = '../dyninst',
  cfg = [[
    --enable-openmp
    --enable-valgrind-annotations
    --with-valgrind=@/external/valgrind@
  ]],
}
