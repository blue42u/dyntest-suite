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

local function szclass(name, sz)
  local cfg = tup.getconfig('VAL_'..name)
  if cfg ~= '' then
    sz = assert(math.tointeger(cfg), 'Configuration option VAL_'
      ..name..' must be a valid integer!')
  end
  return sz
end

local function ruleif(ins, ...)
  if #ins > 0 then tup.rule(ins, ...) end
end

ruleif(forall(function(i)
  if i.size > szclass('MC', 2) then return end
  return {
    id = 'Memcheck', mode = 'ann',
    threads = 32,
    cmd = com..' --tool=memcheck --track-origins=yes %C || :',
    redirect = '/dev/null',
    output = 'mc/%t.%i.log', fakeout = true,
    deps = {'../../external/valgrind/<build>'},
  }
end), '^o Concat %o^ cat %f > %o', {'memcheck.log', '<out>'})

ruleif(forall(function(i)
  if i.size > szclass('HEL', 1) then return end
  return {
    id = 'Helgrind', mode = 'ann',
    threads = 32,
    cmd = llp..com..' --tool=helgrind --free-is-write=yes %C || :',
    redirect = '/dev/null',
    output = 'hg/%t.%i.log', fakeout = true,
    deps = { '../../external/valgrind/<build>'},
  }
end), '^o Concat %o^ cat %f > %o', {'helgrind.log', '<out>'})

ruleif(forall(function(i)
  if i.size > szclass('DRD', 0) then return end
  return {
    id = 'DRD', mode = 'ann',
    threads = 32,
    cmd = llp..com..' --tool=drd --free-is-write=yes %C || :',
    redirect = '/dev/null',
    output = 'drd/%t.%i.log', fakeout = true,
    deps = { '../../external/valgrind/<build>'},
  }
end), '^o Concat %o^ cat %f > %o', {'drd.log', '<out>'})

do
  local big
  local massif = forall(function(i, t)
    if i.size > szclass('MASSIF', 0) then return end
    local o = {
      id = 'Massif', mode = 'ann',
      threads = 32,
      cmd = val..' -q --massif-out-file=%o --tool=massif %C || :',
      redirect = '/dev/null',
      output = 'massif/%t.%i.out', fakeout = true,
      deps = {'../../external/valgrind/<build>'},
      _sz = i.size * t.size,
    }
     if not big or o._sz > big._sz then big = o end
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

do
  local big
  local callgrind = forall(function(i, t)
    if i.size > szclass('CALLGRIND', 0) then return end
    local o = {
      id = 'Callgrind', mode = 'ann',
      threads = 32,
      cmd = val..' -q --callgrind-out-file=%o --tool=callgrind --dump-instr=yes'
        ..' --collect-systime=yes --collect-bus=yes --fair-sched=yes %C || :',
      redirect = '/dev/null',
      output = 'cg/callgrind.out.%t.%i', fakeout = true,
      deps = {'../../external/valgrind/<build>'},
      _sz = i.size * t.size,
    }
    if not big or o._sz > big._sz then big = o end
    return o
  end)
  for i,f in ipairs(callgrind) do
    if i == big.idx then
      tup.rule(f, '^ Copy %f -> %o^ cp %f %o', {'callgrind.out', '<out>'})
    end
  end
end
