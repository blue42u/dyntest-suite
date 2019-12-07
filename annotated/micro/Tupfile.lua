-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/micro.lua'
micro {
  builddir = 'annotated/micro',
  elfutils = '../elfutils',
  dyninst = '../dyninst',
  cppflags = ompcppflags,
  cxxflags = ompcxxflags,
}
