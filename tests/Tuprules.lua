-- luacheck: std lua53, no global (Tup-Lua)

tup.creategitignore()

local cwd = tup.getcwd():gsub('[^/]$', '%0/')

-- List of inputs to test against
inputs = {
  libasm = {
    fn = cwd..'../reference/elfutils/install/lib/libasm.so',
    deps = {cwd..'../reference/elfutils/<libs>'},
    size = 1,
  },
  -- libcommon = {
  --   fn = cwd..'../reference/dyninst/install/lib/libcommon.so',
  --   deps = {cwd..'../reference/dyninst/<libs>'},
  --   size = 2,
  -- },
  -- libdyninst = {
  --   fn = cwd..'../reference/dyninst/install/lib/libdyninstAPI.so',
  --   deps = {cwd..'../reference/dyninst/<libs>'},
  --   size = 2,
  -- },
}

local lzma = cwd..'../external/lzma/<build>'
local elf = cwd..'../latest/elfutils/'
local dyn = cwd..'../latest/dyninst/'
local hpc = cwd..'../latest/hpctoolkit/'
local refelf = cwd..'../reference/elfutils/'
local refdyn = cwd..'../reference/dyninst/'
local refhpc = cwd..'../reference/hpctoolkit/'

-- List of tests to test with
tests = {
  hpcstruct = {
    env = 'OMP_NUM_THREADS=%T',
    fn = cwd..'../latest/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    reffn = cwd..'../reference/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    args = '-j%T --jobs-symtab %T -o %o %f',
    deps = {lzma, elf..'<libs>', dyn..'<libs>', hpc..'<bin>'},
    refdeps = {lzma, refelf..'<libs>', refdyn..'<libs>', refhpc..'<bin>'}
  },
}

local ti,tm = table.insert,tup.append_table

-- The actual rule-creation command, that handles any little oddities
function forall(harness)
  local outs = {}
  for iid,i in pairs(inputs) do for tid,t in pairs(tests) do
    i.id,t.id = iid,tid
    for _,h in ipairs{harness(i, t)} do
      local repl = {
        T = ('%d'):format(h.threads or 1),
      }
      local tfn,tdeps,env = t.fn, t.deps, t.env or ''
      if h.reference then tfn,tdeps,env = t.reffn, t.refdeps, t.refenv or env end

      env = env:gsub('%%(.)', repl)
      local args = (t.args or ''):gsub('%%(.)', repl)
      if h.redirect then args = args:gsub('%%o', h.redirect) end
      if i.deps then args = args:gsub('%%f', i.fn) end

      local flock = 'flock '..cwd
      if not h.noparallel then flock = 'flock -u '..cwd end

      local out = h.output:gsub('%%(.)', { t = tid, i = iid })
      local cmd = env..' '..flock..' '..h.cmd:gsub('%%(.)', {
        T=tfn, A=args, C=tfn..' '..args,
      })
      local name = '^'..(h.rebuild and '' or 'o')..' '
        ..h.id..' '..tid..' '..iid..' ^'

      local ins = {extra_inputs={}}
      if i.deps then tm(ins.extra_inputs, i.deps) else ti(ins, i.fn) end
      if tdeps then tm(ins.extra_inputs, tdeps) else ti(ins, tfn) end
      local fakeaccess = ' stat '..i.fn..' '..tfn
        ..' >/dev/null && touch %o && LD_PRELOAD= '

      tup.rule(ins, name..fakeaccess..cmd, {out})
      table.insert(outs, out)
    end
  end end
  return outs
end
