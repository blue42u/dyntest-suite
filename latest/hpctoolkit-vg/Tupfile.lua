-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/hpctoolkit.lua'
hpctoolkit {
  builddir = 'latest/hpctoolkit',
  elfutils = '../elfutils',
  dyninst = '../dyninst-vg',
  cfg = '--enable-openmp',
}
