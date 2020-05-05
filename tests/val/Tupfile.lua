-- luacheck: std lua53, no global (Tup-Lua)

sclass = 4

tup.include '../../external/valgrind/find.lua'

local val = VALGRIND_CMD

local comopts = '--suppressions=system.supp'
  ..' --fair-sched=yes --read-var-info=no'
  ..' --soname-synonyms=somalloc=\\*tbbmalloc\\*'
  ..' --merge-recursive-frames=1'
local com = val..' --log-file=%o '..comopts
local mpicom = val..' ??LOG?? '..comopts

local function szclass(name, sz)
  local cfg = tup.getconfig('VAL_'..name)
  if cfg ~= '' then
    sz = assert(math.tointeger(cfg), 'Configuration option VAL_'
      ..name..' must be a valid integer!')
  end
  if sz == -1 then sz = math.huge end
  return sz
end

local function expand(base, reg, dry)
  local out = {base}
  if dry then table.insert(out, setmetatable({
    id = base.id..' (dry)', dry = true, redirect = false,
    output = base.output..'.dry',
  }, {__index=base})) end
  if reg then table.insert(out, setmetatable({
    id = base.id..' (reg)', imode = 'ref',
    output = base.output..'.reg',
  }, {__index=base})) end
  if dry and reg then table.insert(out, setmetatable({
    id = base.id..' (dry,reg)', imode = 'ref', dry = true, redirect = false,
    output = base.output..'.dryreg',
  }, {__index=base})) end
  return table.unpack(out)
end

ruleif(forall(function(i, t)
  if i.size > szclass('MC', 2) then return end
  return expand({
    id = 'Memcheck', mode = 'ann',
    threads = 32,
    cmd = (t.mpirun and mpicom or com)
      ..' --tool=memcheck --track-origins=yes --leak-check=full %C || :',
    env = VALGRIND_ENV..(t.mpirun and ' "`pwd`"/tmplog.sh %o' or ''),
    redirect = '/dev/null',
    output = 'mc/%t.%i.log', fakeout = true,
    deps = {'../../external/valgrind/<build>'},
  }, i.modes.ann ~= i.modes.ref, t.dryargs)
end), '^o Concat %o^ cat %f > %o', {'memcheck.log', '<out>'})

ruleif(forall(function(i, t)
  if i.size > szclass('HEL', 1) then return end
  return expand({
    id = 'Helgrind', mode = 'ann',
    threads = 32,
    cmd = (t.mpirun and mpicom or com)
      ..' --tool=helgrind --free-is-write=yes %C || :',
    env = VALGRIND_ENV..(t.mpirun and ' "`pwd`"/tmplog.sh %o' or ''),
    redirect = '/dev/null',
    output = 'hg/%t.%i.log', fakeout = true,
    deps = { '../../external/valgrind/<build>'},
  }, i.modes.ann ~= i.modes.ref)
end), '^o Concat %o^ cat %f > %o', {'helgrind.log', '<out>'})

ruleif(forall(function(i, t)
  if i.size > szclass('DRD', 0) then return end
  return expand({
    id = 'DRD', mode = 'ann',
    threads = 32,
    cmd = (t.mpirun and mpicom or com)
      ..' --tool=drd --free-is-write=yes %C || :',
    env = VALGRIND_ENV..(t.mpirun and ' "`pwd`"/tmplog.sh %o' or ''),
    redirect = '/dev/null',
    output = 'drd/%t.%i.log', fakeout = true,
    deps = { '../../external/valgrind/<build>'},
  }, i.modes.ann ~= i.modes.ref)
end), '^o Concat %o^ cat %f > %o', {'drd.log', '<out>'})

do
  local big
  local massif = forall(function(i, t)
    if i.size > szclass('MASSIF', 0) then return end
    if t.mpirun then return end
    local o = {
      id = 'Massif (dry run)', mode = 'ann', dry = true,
      threads = 32,
      cmd = val..' -q --massif-out-file=%o --tool=massif '..comopts..' %C || :',
      env = VALGRIND_ENV,
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
    if t.mpirun then return end
    local o = {
      id = 'Callgrind', mode = 'ann',
      threads = 32,
      cmd = val..' -q --callgrind-out-file=%o --tool=callgrind --dump-instr=yes'
        ..' --collect-systime=yes --collect-bus=yes '..comopts..' %C || :',
      env = VALGRIND_ENV,
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
