-- luacheck: std lua53, no global

tup.include '../external/cuda/find.lua'
local withcuda = externalProjects.cuda and [[
  --with-cuda=@/external/cuda@
  --with-cupti=@/external/cuda@
]] or ''

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
      --with-mbedtls=@/external/mbedtls@
      --with-elfutils=@]]..o.elfutils..[[@
      --with-dyninst=@]]..o.dyninst..[[@
      --disable-hpcrun-static
    ]]..withcuda..(o.cfg or ''),
  }}
  -- We also munge the paths in the scripts, use .../hpc*.real for best results.
  local ex = o.builddir:gsub('[^/]+', '..'):gsub('/?$', '/')..'external/'
  tup.rule('install/bin/hpcrun', ([=[^o Generated %o^ sed
    -e "/^[[:space:]]*libmonitor_dir/clibmonitor_dir='`realpath ]=]..ex..[=[monitor/install/lib`'"
    -e "/^[[:space:]]*libunwind_dir/clibunwind_dir='`realpath ]=]..ex..[=[unwind/install/lib`'"
    -e "/^[[:space:]]*papi_libdir/cpapi_libdir='`realpath ]=]..ex..[=[papi/install/lib`'"
    -e "/^[[:space:]]*perfmon_libdir/cperfmon_libdir='`realpath ]=]..ex..[=[papi/install/lib`'"
    -e "/HPCRUN_FNBOUNDS_CMD=/s:/hpcfnbounds:\0-bin:"
    -e "/^[[:space:]]*export LD_PRELOAD/iexport HPCTOOLKIT_EXT_LIBS_DIR='`realpath ]=]..ex..[=[dwarf/install/lib`'"
    -e "/^[[:space:]]*hash_value=/chash_value='no'"
    %f > %o && chmod +x %o]=]):gsub('\n%s*', ' '),
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
