-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/dyninst.lua'
dyninst {
  builddir = 'latest/dyninst',
  elfutils = '../elfutils',
}
