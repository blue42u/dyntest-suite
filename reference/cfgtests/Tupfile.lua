-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/cfgtests.lua'
cfgtests {
  builddir = 'reference/cfgtests',
  ref = true,
  elfutils = '../elfutils',
  dyninst = '../dyninst',
}
