-- luacheck: std lua53, no global (Tup-Lua)

sclass = 2

tup.rule('../../reference/hpctoolkit/<build>', '^o Generated %o^ sed'
  ..[[ -e "/^libmonitor_dir/clibmonitor_dir='`realpath ../../external/monitor/install/lib`'"]]
  ..[[ -e "/^libunwind_dir/clibunwind_dir='`realpath ../../external/unwind/install/lib`'"]]
  ..[[ -e "/^papi_libdir/cpapi_libdir='`realpath ../../external/papi/install/lib`'"]]
  ..[[ -e "/^perfmon_libdir/cperfmon_libdir='`realpath ../../external/papi/install/lib`'"]]
  ..[[ -e "/^export HPCRUN_FN/s:/hpcfnbounds:\0-bin:"]]
  ..[[ -e "/^export LD_PRELOAD/iexport HPCTOOLKIT_EXT_LIBS_DIR=]]
  ..[['`realpath ../../external/dwarf/install/lib`'"]]
  ..[[ -e "/^hash_value=/chash_value='no'"]]
  ..' ../../reference/hpctoolkit/install/bin/hpcrun > %o && chmod +x %o', 'hpcrun')

local structs = tup.glob 'struct/*.struct'
for i,s in ipairs(structs) do
  structs[i] = '-S '..s
end
structs = table.concat(structs, ' ')

for _,f in ipairs(forall(function(i, t)
  if i.size < 3 then return end
  if i.id == 'nwchem' and (t.id ~= 'micro-symtab' and t.id ~= 'hpcstruct') then return end
  return {
    id = 'Perf', threads = maxthreads,
    deps = {'hpcrun'},
    cmd = './hpcrun.sh %o %C',
    output = '%t.%i.measurements', serialize = true, redirect = '/dev/null',
  }
end)) do
  tup.rule({f, extra_inputs={'../../reference/hpctoolkit/<build>',
    'struct/<out>', '../src/micro-symtab', serialend()}},
    './hpcprof.sh %f %o '..structs,
    {f:gsub('%.measurements', '.tar'), '../<s_2_post>'})
end

serialfinal()
