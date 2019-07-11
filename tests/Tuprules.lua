-- luacheck: std lua53, no global (Tup-Lua)

tup.creategitignore()

local cwd = tup.getcwd():gsub('[^/]$', '%0/')

-- List of inputs to test against
inputs = {
  libasm = {
    fn = cwd..'../reference/elfutils/install/lib/libasm.so',
    deps = {cwd..'../reference/elfutils/<elfutils>'},
    size = 1,
  },
  libcommon = {
    fn = cwd..'../reference/dyninst/install/lib/libcommon.so',
    deps = {cwd..'../reference/dyninst/<dyninst>'},
    size = 2,
  },
  -- libdyninst = {
  --   fn = cwd..'../reference/dyninst/install/lib/libdyninstAPI.so',
  --   deps = {cwd..'../reference/dyninst/<dyninst>'},
  --   size = 2,
  -- },
}

local lzma = cwd..'../external/lzma/<build>'
local elf = cwd..'../latest/elfutils/<elfutils>'
local dyn = cwd..'../latest/dyninst/<dyninst>'
local hpc = cwd..'../latest/hpctoolkit/<hpctoolkit>'
local refelf = cwd..'../reference/elfutils/<elfutils>'
local refdyn = cwd..'../reference/dyninst/<dyninst>'
local refhpc = cwd..'../reference/hpctoolkit/<hpctoolkit>'

-- List of tests to test with
tests = {
  hpcstruct = {
    env = 'OMP_NUM_THREADS=%T',
    fn = cwd..'../latest/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    reffn = cwd..'../reference/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    args = '-j%T --jobs-symtab %T -o %o %f',
    deps = {lzma, elf, dyn, hpc},
    refdeps = {lzma, refelf, refdyn, refhpc}
  },
}

local ti,tm = table.insert,tup.append_table

-- The actual rule-creation command, that handles any little oddities
function forall(harness)
  local outs = {}
  for iid,i in pairs(inputs) do for tid,t in pairs(tests) do
    for _,h in ipairs{harness(i, t)} do
      local repl = {
        T = ('%d'):format(h.threads or 1),
      }
      local env = (t.env or ''):gsub('%%(.)', repl)
      local args = (t.args or ''):gsub('%%(.)', repl)
      if h.redirect then args = args:gsub('%%o', h.redirect) end
      if i.deps then args = args:gsub('%%f', i.fn) end

      local tfn,tdeps = t.fn, t.deps
      if h.reference then tfn,tdeps = t.reffn, t.refdeps end

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

      tup.rule(ins, name..cmd, {out})
      table.insert(outs, out)
    end
  end end
  return outs
end
