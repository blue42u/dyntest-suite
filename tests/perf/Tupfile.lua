-- luacheck: std lua53, no global (Tup-Lua)

sclass = 2

local tbbpreload = ''
if tup.getconfig 'SLOW_LIBC' == 'y' then
  local tbblib = '../../external/tbb/install/lib/'
  tbbpreload = 'LD_LIBRARY_PATH='..tbblib
    ..' LD_PRELOAD="$LD_PRELOAD":'..tbblib..'libtbbmalloc_proxy.so '
end
local hpcrun = '../../reference/hpctoolkit/install/bin/hpcrun.real'
local env = ''
if tup.getconfig 'TMPDIR' ~= '' then
  env = 'TMPDIR="'..tup.getconfig 'TMPDIR'..'" '
end

local detailed = {}
if enabled('PERF_DETAIL', true) then
detailed = forall(function(i)
  if i.size < 3 then return end
  return {
    id = 'Perf (detailed)', threads = maxthreads,
    env = tbbpreload, tartrans = true,
    cmd = hpcrun..' -e REALTIME@100 -t -o @@%o %C',
    output = 'measurements/%t.%i.tar', serialize = true, redirect = '/dev/null',
  }
end)
end

local rep = 3
if tup.getconfig 'PERF_REP' ~= '' then
  rep = assert(math.tointeger(tup.getconfig 'PERF_REP'),
    'Configuration option PERF_REP must be a valid integer!')
end

local numthreads = {maxthreads}
if tup.getconfig 'PERF_COARSE_THREADS' ~= '' then
  local ts = {}
  for w in tostring(tup.getconfig 'PERF_COARSE_THREADS'):gmatch '[^,]+' do
    w = assert(math.tointeger(w),
      'Configuration option PERF_COARSE_THREADS must be a comma-separated sequence of integers!')
    ts[w] = true
  end
  assert(next(ts), 'Configuration option PERF_COARSE_THREADS cannot be empty!')
  numthreads = {}
  for t in pairs(ts) do table.insert(numthreads, t) end
  table.sort(numthreads)
end

local coarse = {}
if rep > 0 then for _,nt in ipairs(numthreads) do
forall(function(i)
  if i.size < 3 then return end
  local outs = {}
  for r=1,rep do
    table.insert(outs, {
      id = 'Perf (coarse, rep '..r..', '..nt..' threads)', threads=nt,
      env = tbbpreload, tartrans = true,
      cmd = hpcrun..' -e REALTIME@2000 -t -o @@%o %C',
      redirect = '/dev/null',
      output = 'measurements/%t.%i.'..r..'.t'..nt..'.tar', serialize = nt > 1,
    })
  end
  return table.unpack(outs)
end, function(c, i, t) if #c > 0 then table.insert(coarse, {c, i, t, nt}) end end)
end end

local prof = '../../reference/hpctoolkit/install/bin/hpcprof.real'

for _,f in ipairs(detailed) do
  tup.rule({f, extra_inputs={serialend()}},
    '^o Prof %o^ '..env..'../../tartrans.sh '..prof..' '..structs..' -o @@%o @%f ',
    {f:gsub('measurements/', 'detailed/'), serialpost()})
end

local stats = {}
for _,x in ipairs(coarse) do
  local c,i,t,nt = x[1], x[2], x[3], x[4]
  local lats,tlats = {},{}
  for _,f in ipairs(c) do
    local o = f:gsub('measurements/', 'coarse/')
    tup.rule({f, extra_inputs={serialend()}},
      '^o Prof %o^ '..env..'../../tartrans.sh '..prof..' '..structs..' -o @@%o @%f ', o)
    table.insert(lats, o)
    table.insert(tlats, '@'..o)
  end
  lats.extra_inputs = {'../../external/lua/luaexec'}
  local out = 'stats/'..(t.id..'.'..i.id..'.t'..nt..'.lua'):gsub('/','.')
  tup.rule(lats, '^o Dump %o^ '..env..'../../tartrans.sh ../../external/lua/luaexec '
    ..'hpcdump.lua %o '..table.concat(tlats, ' '), {out})
  local id = (t.id..'.'..i.id):gsub('/','.')
  stats[id] = stats[id] or {}
  stats[id][nt] = out
end
for id,fs in pairs(stats) do
  local ins = {extra_inputs={'../../external/lua/luaexec'}}
  local tins = {}
  for nt,f in pairs(fs) do ins[#ins+1],tins[#tins+1] = f, nt..':'..f end
  table.sort(ins)
  table.sort(tins)
  tup.rule(ins, '^o Dumpcat %o^ '..env..'../../external/lua/luaexec '
    ..'hpccat.lua %o '..table.concat(tins, ' '), {'stats/'..id..'.lua', serialpost()})
end

serialfinal()
