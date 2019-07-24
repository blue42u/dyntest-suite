-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/dyninst.lua'
dyninst {
  builddir = 'reference/dyninst',
  elfutils = '../elfutils',
  ref = true,
  cfg = '-DUSE_OpenMP=OFF',
}
