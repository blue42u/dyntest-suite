-- luacheck: std lua53, no global (Tup-Lua)

sclass = 2

local tbblib = '../../external/tbb/install/lib/'
local tbbpreload = 'LD_LIBRARY_PATH='..tbblib
  ..' LD_PRELOAD="$LD_PRELOAD":'..tbblib..'libtbbmalloc_proxy.so '
local hpcrun = '../../reference/hpctoolkit/install/bin/hpcrun.real'

local detailed = {}
if enabled('PERF_DETAIL', true) then
detailed = forall(function(i)
  if i.size < 3 then return end
  return {
    id = 'Perf (detailed)', threads = maxthreads,
    cmd = tbbpreload..'../../tartrans.sh '..hpcrun..' -e REALTIME@100 -t -o @@%o %C',
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
      cmd = tbbpreload..'../../tartrans.sh '..hpcrun..' -e REALTIME@2000 -t -o @@%o %C',
      redirect = '/dev/null',
      output = 'measurements/%t.%i.'..r..'.tar', serialize = true,
    })
  end
  return table.unpack(outs)
end, function(c, i, t) if #c > 0 then table.insert(coarse, {c, i, t}) end end)
end

local prof = '../../reference/hpctoolkit/install/bin/hpcprof.real'

for _,f in ipairs(detailed) do
  tup.rule({f, extra_inputs={serialend()}},
    '^o Prof %o^ ../../tartrans.sh '..prof..' '..structs..' -o @@%o @%f ',
    {f:gsub('measurements/', 'detailed/'), serialpost()})
end

for _,x in ipairs(coarse) do
  local c,i,t = x[1], x[2], x[3]
  local lats,tlats = {},{}
  for _,f in ipairs(c) do
    local o = f:gsub('measurements/', 'coarse/')
    tup.rule({f, extra_inputs={serialend()}},
      '^o Prof %o^ ../../tartrans.sh '..prof..' '..structs..' -o @@%o @%f ', o)
    table.insert(lats, o)
    table.insert(tlats, '@'..o)
  end
  lats.extra_inputs = {'../../external/lua/luaexec'}
  tup.rule(lats, '^o Dump %o^ ../../tartrans.sh ../../external/lua/luaexec '
    ..'hpcdump.lua %o '..table.concat(tlats, ' '),
    {'stats/'..(t.id..'.'..i.id..'.lua'):gsub('/','.'), serialpost()})
end

serialfinal()
