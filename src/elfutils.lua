-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../build/build.lua'
function elfutils(o) return build {
  srcdir = 'src/'..(o.ref and 'ref-' or '')..'elfutils',
  builddir = o.builddir,
  cfgflags = '--enable-maintainer-mode '..(o.cfg or ''),
} end
