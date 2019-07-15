-- luacheck: std lua53, no global (Tup-Lua)

tup.rule('../../reference/hpctoolkit/<bin>', '^o Generated %o^ sed'
  ..[[ -e "/^libmonitor_dir/clibmonitor_dir='`realpath ../../external/monitor/lib`'"]]
  ..[[ -e "/^libunwind_dir/clibunwind_dir='`realpath ../../external/unwind/lib`'"]]
  ..[[ -e "/^papi_libdir/cpapi_libdir='`realpath ../../external/papi/lib`'"]]
  ..[[ -e "/^perfmon_libdir/cperfmon_libdir='`realpath ../../external/papi/lib`'"]]
  ..[[ -e "/^export HPCRUN_FN/s:/hpcfnbounds:\0-bin:"]]
  ..[[ -e "/^export LD_PRELOAD/iexport HPCTOOLKIT_EXT_LIBS_DIR=]]
  ..[['`realpath ../../external/dwarf/lib`'"]]
  ..' ../../reference/hpctoolkit/install/bin/scripts/hpcrun > %o && chmod +x %o', 'hpcrun')

forall(function()
  return {
    id = 'Perf', threads = 8,
    deps = {
      'hpcrun', '../../external/monitor/<build>',
      '../../external/unwind/<build>', '../../external/papi/<build>',
      '../../reference/hpctoolkit/<libs>'
    },
    cmd = './hpcrun -o %o.tmp %C && tar -C %o.tmp -cf %o . && LD_PRELOAD= rm -rf %o.tmp',
    output = '%t.%i.run.8.tar', serialize = true, redirect = '/dev/null',
  }
end)
