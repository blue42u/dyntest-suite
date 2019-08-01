-- luacheck: std lua53, no global (Tup-Lua)

tup.include '../../external/valgrind/find.lua'

local val = VALGRIND_CMD

local llp = ''
if tup.getconfig 'ENABLE_OMP_DEBUG' ~= '' then
  llp = 'LD_LIBRARY_PATH="'..tup.getconfig 'ENABLE_OMP_DEBUG'..'" '
end
local com = val..' --log-file=%o --suppressions=system.supp'
  ..' --fair-sched=yes'
  ..' --soname-synonyms=somalloc=\\*tbbmalloc\\*'

local sz = 2
if tup.getconfig 'VAL_CLASS' ~= '' then
  sz = assert(math.tointeger(tup.getconfig 'VAL_CLASS'),
    'Configuration option VAL_CLASS must be a valid integer!')
end

if not enabled('TEST_VAL', true) then return end

if sz > 0 and enabled('TEST_MEMCHECK', true) then
tup.rule(forall(function(i)
  if i.size > sz-1 then return end
  return {
    id = 'Memcheck', mode = 'ann',
    threads = 32,
    cmd = com..' --tool=memcheck %C',
    redirect = '/dev/null',
    output = 'mc/%t.%i.log', fakeout = true,
    deps = {'../../external/valgrind/<build>'},
  }
end), '^o Concat %o^ cat %f > %o', {'memcheck.log', '<out>'})
end

if sz > 1 and enabled('TEST_HELGRIND', true) then
tup.rule(forall(function(i, t)
  if i.size > sz-1 then return end
  if t.id == 'hpcstruct' and i.id == 'libdw' then return end
  return {
    id = 'Helgrind', mode = 'ann',
    threads = 32,
    cmd = llp..com..' --tool=helgrind %C',
    redirect = '/dev/null',
    output = 'hg/%t.%i.log', fakeout = true,
    deps = { '../../external/valgrind/<build>'},
  }
end), '^o Concat %o^ cat %f > %o', {'helgrind.log', '<out>'})
end

if sz > 2 and enabled('TEST_DRD', true) then
tup.rule(forall(function(i)
  if i.size > sz-2 then return end
  return {
    id = 'DRD', mode = 'ann',
    threads = 32,
    cmd = llp..com..' --tool=drd %C',
    redirect = '/dev/null',
    output = 'drd/%t.%i.log', fakeout = true,
    deps = { '../../external/valgrind/<build>'},
  }
end), '^o Concat %o^ cat %f > %o', {'drd.log', '<out>'})
end

if sz > 0 and enabled('TEST_MASSIF', false) then
local big,bigsize
local massif = forall(function(i, t)
  if i.size > sz then return end
  local o = {
    id = 'Massif', mode = 'ann',
    threads = 32,
    cmd = val..' -q --massif-out-file=%o --tool=massif %C',
    redirect = '/dev/null',
    output = 'massif/%t.%i.out', fakeout = true,
    deps = {'../../external/valgrind/<build>'},
  }
  if not big or i.size*t.size > bigsize then big,bigsize = o,i.size*t.size end
  return o
end)
for i,f in ipairs(massif) do
  local o = f:gsub('%.out$', '.dump')
  tup.rule({f, extra_inputs={'../../external/valgrind/<build>'}},
    '^ Massif Dump %f -> %o^ '..VALGRIND_MS_PRINT..' %f > %o', o)
  if i == big.idx then
    tup.rule(o, '^ Copy %f -> %o^ cp %f %o', {'massif.dump', '<out>'})
  end
end
end

if sz > 0 and enabled('TEST_CALLGRIND', false) then
local big,bigsize
local callgrind = forall(function(i, t)
  if i.size > sz then return end
  local o = {
    id = 'Callgrind', mode = 'ann',
    threads = 32,
    cmd = val..' -q --callgrind-out-file=%o --tool=callgrind --dump-instr=yes'
      ..' --collect-systime=yes --collect-bus=yes --fair-sched=yes %C',
    redirect = '/dev/null',
    output = 'cg/callgrind.out.%t.%i', fakeout = true,
    deps = {'../../external/valgrind/<build>'},
  }
  if not big or i.size*t.size > bigsize then big,bigsize = o,i.size*t.size end
  return o
end)
for i,f in ipairs(callgrind) do
  if i == big.idx then
    tup.rule(f, '^ Copy %f -> %o^ cp %f %o', {'callgrind.out', '<out>'})
  end
end
end
