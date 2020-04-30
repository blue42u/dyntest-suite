-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/cfgtests.lua'
cfgtests {
  builddir = 'latest/cfgtests',
  elfutils = '../elfutils',
  dyninst = '../dyninst',
}
