-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/micro.lua'
micro {
  builddir = 'latest/micro',
  elfutils = '../elfutils',
  dyninst = '../dyninst',
}
