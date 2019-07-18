-- luacheck: std lua53, no global (Tup-Lua)

local llp = 'LD_LIBRARY_PATH=../../external/gcc/lib '
local lds = '../../external/gcc/<build>'

tup.rule('../../reference/hpctoolkit/<bin>', '^o Generated %o^ sed'
  ..[[ -e "/^libmonitor_dir/clibmonitor_dir='`realpath ../../external/monitor/lib`'"]]
  ..[[ -e "/^libunwind_dir/clibunwind_dir='`realpath ../../external/unwind/lib`'"]]
  ..[[ -e "/^papi_libdir/cpapi_libdir='`realpath ../../external/papi/lib`'"]]
  ..[[ -e "/^perfmon_libdir/cperfmon_libdir='`realpath ../../external/papi/lib`'"]]
  ..[[ -e "/^export HPCRUN_FN/s:/hpcfnbounds:\0-bin:"]]
  ..[[ -e "/^export LD_PRELOAD/iexport HPCTOOLKIT_EXT_LIBS_DIR=]]
  ..[['`realpath ../../external/dwarf/lib`'"]]
  ..' ../../reference/hpctoolkit/install/bin/scripts/hpcrun > %o && chmod +x %o', 'hpcrun')

for _,f in ipairs(forall(function(i, t)
  if i.size < 3 then return end
  if i.id == 'nwchem' and (t.id ~= 'micro-symtab' and t.id ~= 'hpcstruct') then return end
  return {
    id = 'Perf', threads = 8,
    deps = {
      'hpcrun', '../../external/monitor/<build>', '../../external/dwarf/<build>',
      '../../external/unwind/<build>', '../../external/papi/<build>',
      '../../reference/dyninst/<libs>',
      '../../reference/hpctoolkit/<libs>', lds,
    },
    cmd = llp..'./hpcrun -e REALTIME@100 -t -o %o.tmp %C && '
      ..'tar -C %o.tmp -cJf %o . && LD_PRELOAD= rm -rf %o.tmp',
    output = '%t.%i.measurements.txz', serialize = true, redirect = '/dev/null',
  }, {
    id = 'Perf (singlethreaded)', threads = 1,
    deps = {
      'hpcrun', '../../external/monitor/<build>', '../../external/dwarf/<build>',
      '../../external/unwind/<build>', '../../external/papi/<build>',
      '../../reference/dyninst/<libs>',
      '../../reference/hpctoolkit/<libs>', lds,
    },
    cmd = llp..'./hpcrun -e REALTIME@100 -t -o %o.tmp %C && '
      ..'tar -C %o.tmp -cJf %o . && LD_PRELOAD= rm -rf %o.tmp',
    output = '%t.%i.1.measurements.txz', serialize = true, redirect = '/dev/null',
  }
end)) do
  local untar = 'tar xJf %f --one-top-level=%o.tmpa'
  local prof = '../../reference/hpctoolkit/install/bin/hpcprof -o %o.tmpb %o.tmpa'
  local retar = 'tar -C %o.tmpb -cJf %o .'
  local clean = 'rm -rf %o.tmpa %o.tmpb'
  tup.rule({f, extra_inputs={'../../reference/hpctoolkit/<bin>'}},
    table.concat({untar, prof, retar, clean}, ' && '),
    f:gsub('measurements%.', ''))
end
