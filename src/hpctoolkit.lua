-- luacheck: std lua53, no global

tup.include '../build/build.lua'
function hpctoolkit(o)
  local r = {build {
    srcdir = 'src/'..(o.ref and 'ref-' or '')..'hpctoolkit',
    builddir = o.builddir,
    cfgflags = [[
      --with-boost=@/external/boost@
      --with-tbb=@/external/tbb@
      --with-xerces=@/external/xerces@
      --with-libdwarf=@/external/dwarf@
      --with-binutils=@/external/binutils@
      --with-zlib=@/external/zlib@
      --with-lzma=@/external/lzma@
      --with-xed=@/external/xed@
      --with-libunwind=@/external/unwind@
      --with-perfmon=@/external/papi@
      --with-libmonitor=@/external/monitor@
      --with-bzip=@/external/bzip@
      --with-elfutils=@]]..o.elfutils..[[@
      --with-dyninst=@]]..o.dyninst..[[@
      --disable-hpcrun-static
    ]]..(o.cfg or ''),
  }}
  -- We also munge the paths in the scripts, use .../hpc*.real for best results.
  local ex = o.builddir:gsub('[^/]+', '..'):gsub('/?$', '/')..'external/'
  tup.rule('install/bin/hpcrun', ([[^o Generated %o^ sed
    -e "/^libmonitor_dir/clibmonitor_dir='`realpath ]]..ex..[[monitor/install/lib`'"
    -e "/^libunwind_dir/clibunwind_dir='`realpath ]]..ex..[[unwind/install/lib`'"
    -e "/^papi_libdir/cpapi_libdir='`realpath ]]..ex..[[papi/install/lib`'"
    -e "/^perfmon_libdir/cperfmon_libdir='`realpath ]]..ex..[[papi/install/lib`'"
    -e "/^export HPCRUN_FN/s:/hpcfnbounds:\0-bin:"
    -e "/^export LD_PRELOAD/iexport HPCTOOLKIT_EXT_LIBS_DIR='`realpath ]]..ex..[[dwarf/install/lib`'"
    -e "/^hash_value=/chash_value='no'"
    %f > %o && chmod +x %o]]):gsub('\n%s*', ' '),
    {'install/bin/hpcrun.real', '<build>'})
  tup.rule('install/libexec/hpctoolkit/hpcprof-bin',
    '^o Linked %o^ ln -s ../libexec/hpctoolkit/hpcprof-bin %o',
    {'install/bin/hpcprof.real', '<build>'})
  tup.rule('install/libexec/hpctoolkit/hpcprof-mpi-bin',
    '^o Linked %o^ ln -s ../libexec/hpctoolkit/hpcprof-mpi-bin %o',
    {'install/bin/hpcprof-mpi.real', '<build>'})
  if #tup.glob 'install/libexec/hpctoolkit/hpcprofmock-bin' ~= 0 then
  tup.rule('install/libexec/hpctoolkit/hpcprofmock-bin',
    '^o Linked %o^ ln -s ../libexec/hpctoolkit/hpcprofmock-bin %o',
    {'install/bin/hpcprofmock.real', '<build>'})
  end
  tup.rule('install/libexec/hpctoolkit/hpcstruct-bin',
    '^o Linked %o^ ln -s ../libexec/hpctoolkit/hpcstruct-bin %o',
    {'install/bin/hpcstruct.real', '<build>'})
  return table.unpack(r)
end
