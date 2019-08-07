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

local detailed = forall(function(i)
  if i.size < 3 then return end
  return {
    id = 'Perf (detailed)', threads = maxthreads,
    deps = {'hpcrun'},
    cmd = './hpcrun.sh 100 %o %C',
    output = 'measurements/%t.%i.tar', serialize = true, redirect = '/dev/null',
  }
end)

local rep = 3
if tup.getconfig 'PERF_REP' ~= '' then
  rep = assert(math.tointeger(tup.getconfig 'PERF_REP'),
    'Configuration option PERF_REP must be a valid integer!')
end

local coarse = {}
forall(function(i)
  if i.size < 3 then return end
  local outs = {}
  for r=1,rep do
    table.insert(outs, {
      id = 'Perf (coarse, rep '..r..')', threads=maxthreads,
      deps = {'hpcrun'},
      cmd = './hpcrun.sh 2000 %o %C', redirect = '/dev/null',
      output = 'measurements/%t.%i.'..r..'.tar', serialize = true,
    })
  end
  return table.unpack(outs)
end, function(c, i, t) if #c > 0 then table.insert(coarse, {c, i, t}) end end)

for _,f in ipairs(detailed) do
  tup.rule({f, extra_inputs={'../../reference/hpctoolkit/<build>',
    'struct/<out>', serialend()}},
    '^o Prof %o^ ./hpcprof.sh %f %o '..structs,
    {f:gsub('measurements/', 'detailed/'), '../<s_2_post>'})
end

for _,x in ipairs(coarse) do
  local c,i,t = x[1], x[2], x[3]
  local lats = {}
  for _,f in ipairs(c) do
    local o = f:gsub('measurements/', 'coarse/')
    tup.rule({f, extra_inputs={'../../reference/hpctoolkit/<build>',
      'struct/<out>', serialend()}},
      '^o Prof %o^ ./hpcprof.sh %f %o '..structs, o)
    table.insert(lats, o)
  end
  lats.extra_inputs = {'../../external/lua/luaexec'}
  tup.rule(lats, '^o Dump %o^ ./hpcdump.sh %o %f',
    {'stats/'..t.id..'.'..i.id..'.lua', '../<s_2_post>'})
end

serialfinal()
