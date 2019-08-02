-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/hpctoolkit.lua'
hpctoolkit {
  builddir = 'serial/hpctoolkit',
  elfutils = '../../latest/elfutils',
  dyninst = '../dyninst',
  cfg = '--disable-openmp CFLAGS=-DSERIALMODE',
}
