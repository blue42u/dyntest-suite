-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/cfgtests.lua'
cfgtests {
  builddir = 'annotated/cfgtests',
  elfutils = '../elfutils',
  dyninst = '../dyninst',
  cppflags = ompcppflags,
  cxxflags = ompcxxflags,
}
