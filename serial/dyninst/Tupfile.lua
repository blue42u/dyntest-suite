-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../src/dyninst.lua'
dyninst {
  builddir = 'serial/dyninst',
  elfutils = '../../latest/elfutils',
  cfg = [[
    -DCMAKE_CXX_FLAGS="-DSERIALMODE"
    -DUSE_OpenMP=OFF
  ]],
}
