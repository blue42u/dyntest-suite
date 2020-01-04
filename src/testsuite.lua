-- luacheck: std lua53, no global

function testsuite() end

tup.include '../build/build.lua'
function testsuite(o)
  local r = {build {
    srcdir = 'src/testsuite',
    builddir = o.builddir,
    cfgflags = [[
      -DDyninst_SRC_DIR=@@/src/dyninst
      -DDyninst_ROOT=@]]..o.dyninst..[[@
      -DElfUtils_ROOT_DIR=@]]..o.elfutils..[[@
      -DTBB_ROOT_DIR=@/external/tbb@
      -DBoost_ROOT_DIR=@/external/boost@
      -DLibXml2_ROOT=@/external/libxml@
    ]]..(o.cfg or ''),
  }}

  -- Symlink install/lib to install/bin/testsuite, because someone had a bright idea.
  tup.rule([[^o Linked %o^ ln -s bin/testsuite %o]], {'install/lib', '<build>'})

  return table.unpack(r)
end
