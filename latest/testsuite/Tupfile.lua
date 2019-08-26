-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/testsuite.lua'
testsuite {
  builddir = 'latest/testsuite',
  elfutils = '../elfutils',
  dyninst = '../dyninst',
}
