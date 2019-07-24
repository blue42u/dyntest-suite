-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/elfutils.lua'
elfutils{
  builddir = 'reference/elfutils',
  ref = true,
}
