-- luacheck: std lua53, no global (Tup-Lua)

sclass = 2

local structs = tup.glob 'struct/*.struct'
for i,s in ipairs(structs) do
  structs[i] = '-S '..s
end
structs = table.concat(structs, ' ')

local detailed = {}
if enabled('PERF_DETAIL', true) then
detailed = forall(function(i)
  if i.size < 3 then return end
  return {
    id = 'Perf (detailed)', threads = maxthreads,
    deps = {'hpcrun'},
    cmd = './hpcrun.sh 100 %o %C',
    output = 'measurements/%t.%i.tar', serialize = true, redirect = '/dev/null',
  }
end)
end

local rep = 3
if tup.getconfig 'PERF_REP' ~= '' then
  rep = assert(math.tointeger(tup.getconfig 'PERF_REP'),
    'Configuration option PERF_REP must be a valid integer!')
end

local coarse = {}
if rep > 0 then
forall(function(i)
  if i.size < 3 then return end
  local outs = {}
  for r=1,rep do
    table.insert(outs, {
      id = 'Perf (coarse, rep '..r..')', threads=maxthreads,
      cmd = './hpcrun.sh 2000 %o %C', redirect = '/dev/null',
      output = 'measurements/%t.%i.'..r..'.tar', serialize = true,
    })
  end
  return table.unpack(outs)
end, function(c, i, t) if #c > 0 then table.insert(coarse, {c, i, t}) end end)
end

if enabled('PERF_DETAIL', true) then
for _,f in ipairs(detailed) do
  tup.rule({f, extra_inputs={'../../reference/hpctoolkit/<build>',
    'struct/<out>', serialend()}},
    '^o Prof %o^ ./hpcprof.sh %f %o '..structs,
    {f:gsub('measurements/', 'detailed/'), serialpost()})
end
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
    {'stats/'..t.id..'.'..i.id..'.lua', serialpost()})
end

serialfinal()
