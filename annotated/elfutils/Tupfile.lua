-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/elfutils.lua'
elfutils{
  builddir = 'annotated/elfutils',
  cfg = [[
    --with-valgrind=@/external/valgrind@/include
    --enable-valgrind-annotations
  ]],
}
