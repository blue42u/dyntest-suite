-- luacheck: std lua53, no global (Tup-Lua)

tup.creategitignore()

local cwd = tup.getcwd():gsub('[^/]$', '%0/')

local lzma = cwd..'../external/lzma/<build>'
local tbb = cwd..'../external/tbb/<build>'
local boost = cwd..'../external/boost/<build>'

-- List of inputs to test against
inputs = {
  { id = 'libasm',
    fn = cwd..'../latest/elfutils/install/lib/libasm.so',
    deps = {lzma, cwd..'../latest/elfutils/<libs>'},
    size = 1,
  },
  { id = 'libdw',
    fn = cwd..'../latest/elfutils/install/lib/libdw.so',
    deps = {lzma, cwd..'../latest/elfutils/<libs>'},
    size = 1,
  },
  { id = 'libcommon',
    fn = cwd..'../latest/dyninst/install/lib/libcommon.so',
    deps = {lzma, tbb, boost, cwd..'../latest/dyninst/<libs>'},
    size = 2,
  },
  { id = 'libdyninst',
    fn = cwd..'../latest/dyninst/install/lib/libdyninstAPI.so',
    deps = {lzma, tbb, boost, cwd..'../latest/dyninst/<libs>'},
    size = 3,
  },
  { id = 'hpcstruct',
    fn = cwd..'../latest/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    deps = {lzma, tbb, boost, cwd..'../latest/hpctoolkit/<bin>'},
    size = 3,
  },
}

local elf = cwd..'../latest/elfutils/'
local dyn = cwd..'../latest/dyninst/'
local hpc = cwd..'../latest/hpctoolkit/'
local refelf = cwd..'../reference/elfutils/'
local refdyn = cwd..'../reference/dyninst/'
local refhpc = cwd..'../reference/hpctoolkit/'

-- List of tests to test with
tests = {
  { id = 'hpcstruct',
    size = 3,
    env = 'OMP_NUM_THREADS=%T',
    fn = cwd..'../latest/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    reffn = cwd..'../reference/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    args = '-j%T --jobs-symtab %T -o %o %f',
    deps = {tbb, boost, elf..'<libs>', dyn..'<libs>', hpc..'<bin>'},
    refdeps = {tbb, boost, refelf..'<libs>', refdyn..'<libs>', refhpc..'<bin>'},
    outclean = [=[sed -e 's/i="[[:digit:]]\+"/i="NNNNN"/g' %f > %o]=],
  },
  { id = 'unstrip',
    size = 2,
    env = 'OMP_NUM_THREADS=%T',
    fn = cwd..'../latest/dyninst/install/bin/unstrip',
    reffn = cwd..'../reference/dyninst/install/bin/unstrip',
    args = '-f %f -o %o',
    deps = {tbb, boost, elf..'<libs>', dyn..'<bin>'},
    refdeps = {tbb, boost, refelf..'<libs>', refdyn..'<bin>'},
  },
  { id = 'micro-symtab',
    size = 0,
    env = 'OMP_NUM_THREADS=%T',
    fn = cwd..'src/micro-symtab', reffn = cwd..'src/micro-symtab-ref',
    args = '%f > %o',
    deps = {tbb, boost, elf..'<libs>', dyn..'<bin>', cwd..'src/micro-symtab'},
    refdeps = {tbb, boost, refelf..'<libs>', refdyn..'<bin>', cwd..'src/micro-symtab-ref'},
  },
}

local ti,tm = table.insert,tup.append_table

-- The actual rule-creation command, that handles any little oddities
local lastsg
function forall(harness, post)
  local allouts = {}
  for _,i in ipairs(inputs) do for _,t in ipairs(tests) do
    if t.id ~= 'unstrip' or i.id ~= 'libasm' and i.id ~= 'libdw' then
    local single = {}
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

      local out = h.output:gsub('%%(.)', { t = t.id, i = i.id })
      local cmd = env..' '..h.cmd:gsub('%%(.)', {
        T=tfn, A=args, C=tfn..' '..args,
      })
      local name = '^'..(h.rebuild and '' or 'o')..' '
        ..h.id..' '..t.id..' '..i.id..' ^'

      local ins = {extra_inputs={}}
      if i.deps then tm(ins.extra_inputs, i.deps) else ti(ins, i.fn) end
      if tdeps then tm(ins.extra_inputs, tdeps) else ti(ins, tfn) end
      if h.deps then tm(ins.extra_inputs, h.deps) end

      local outs = {out}
      if h.serialize then
        ti(ins.extra_inputs, lastsg and cwd..('<s_%d>'):format(lastsg) or cwd..'<s_init>')
        lastsg = (lastsg or 0) + 1
        ti(outs, cwd..('<s_%d>'):format(lastsg))
      else ti(outs, cwd..'<s_init>') end

      local fakeaccess = ' stat '..i.fn..' '..tfn
        ..' >/dev/null && touch %o && LD_PRELOAD= '

      tup.rule(ins, name..fakeaccess..cmd, outs)
      if post then table.insert(single, out) else
        table.insert(allouts, out)
        h.idx = #outs
      end
    end
    if post then tm(allouts, post(single, i, t) or {}) end
    end
  end end
  return allouts
end
