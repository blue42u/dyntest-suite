-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/micro.lua'
micro {
  builddir = 'reference/micro',
  ref = true,
  elfutils = '../elfutils',
  dyninst = '../dyninst',
}
