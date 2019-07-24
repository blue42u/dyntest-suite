-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/hpctoolkit.lua'
hpctoolkit {
  builddir = 'reference/hpctoolkit',
  ref = true,
  elfutils = '../elfutils',
  dyninst = '../dyninst',
  cfg = '--disable-openmp',
}
