-- luacheck: std lua53, no global (Tup-Lua)

tup.creategitignore()

function enabled(n, default)
  assert(default ~= nil)
  n = tup.getconfig(n)
  if n == 'y' or n == 'Y' then return true
  elseif n == 'n' or n == 'N' then return false
  elseif n == '' then return not not default
  else error('Configuration option '..n..' must be y/Y or n/N!') end
end

if tup.getconfig 'MAX_THREADS' ~= '' then
  maxthreads = assert(math.tointeger(tup.getconfig 'MAX_THREADS'),
    'Configuration option MAX_THREADS must be a valid integer!')
else
  maxthreads = 0
  for l in io.lines '/proc/cpuinfo' do
    if l:find '^processor%s*:' then maxthreads = maxthreads + 1 end
  end
  assert(maxthreads ~= 0, 'Error getting thread count!')
end

local cwd = tup.getcwd():gsub('[^/]$', '%0/')

local alldeps = {}
for _,d in ipairs{
  '../external/lzma', '../external/tbb', '../external/boost',
  '../external/monitor', '../external/dwarf', '../external/unwind',
  '../external/papi', '../external/zlib', '../external/bzip',
  '../external/gcc',
  '../latest/elfutils', '../latest/dyninst', '../latest/dyninst-vg',
  '../latest/hpctoolkit', '../latest/hpctoolkit-vg', '../reference/elfutils',
  '../reference/dyninst', '../reference/hpctoolkit',
} do
  table.insert(alldeps, cwd..d..'/<build>')
end

-- List of inputs to test against
inputs = {
  { id = 'libasm', grouped = true,
    fn = cwd..'../latest/elfutils/install/lib/libasm.so',
    size = 1,
  },
  { id = 'libdw', grouped = true,
    fn = cwd..'../latest/elfutils/install/lib/libdw.so',
    size = 1,
  },
  { id = 'libcommon', grouped = true,
    fn = cwd..'../latest/dyninst/install/lib/libcommon.so',
    size = 2,
  },
  { id = 'libdyninst', grouped = true,
    fn = cwd..'../latest/dyninst/install/lib/libdyninstAPI.so',
    size = 3,
  },
  { id = 'hpcstruct', grouped = true,
    fn = cwd..'../latest/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    size = 3,
  },
}
for _,f in ipairs(tup.glob(cwd..'/extras/*')) do
  local id = f:match '[^/]+$'
  if id ~= '.gitignore' then table.insert(inputs, {id=id, fn=f, size=10}) end
end

-- List of tests to test with
tests = {
  { id = 'hpcstruct',
    size = 3, grouped = true,
    env = 'OMP_NUM_THREADS=%T',
    fn = cwd..'../latest/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    annfn = cwd..'../latest/hpctoolkit-vg/install/libexec/hpctoolkit/hpcstruct-bin',
    reffn = cwd..'../reference/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    args = '-j%T --jobs-symtab %T -o %o %f',
    outclean = [=[sed -e 's/i="[[:digit:]]\+"/i="NNNNN"/g' %f > %o]=],
  },
  { id = 'unstrip',
    size = 2, grouped = true,
    env = 'OMP_NUM_THREADS=%T',
    fn = cwd..'../latest/dyninst/install/bin/unstrip',
    annfn = cwd..'../latest/dyninst-vg/install/bin/unstrip',
    reffn = cwd..'../reference/dyninst/install/bin/unstrip',
    args = '-f %f -o %o',
  },
  { id = 'micro-symtab',
    size = 0,
    env = 'OMP_NUM_THREADS=%T',
    fn = cwd..'src/micro-symtab',
    annfn = cwd..'src/micro-symtab-ann',
    reffn = cwd..'src/micro-symtab-ref',
    args = '%f > %o',
  },
}

local ti,tm = table.insert,tup.append_table

local lastsg
function serialend()
  return lastsg and cwd..('<s_%d_%d>'):format(sclass, lastsg)
    or sclass == 1 and cwd..'<s_init>' or cwd..('<s_%d_post>'):format(sclass-1)
end

-- The actual rule-creation command, that handles any little oddities
function forall(harness, post)
  local cnt = 0
  local clusters, is, ts = {},{},{}
  for _,i in ipairs(inputs) do for _,t in ipairs(tests) do
    if t.id ~= 'unstrip' or i.id ~= 'libasm' and i.id ~= 'libdw' then
    local single = {}
    for _,h in ipairs{harness(i, t)} do
      local repl = {
        T = ('%d'):format(h.threads or 1),
      }
      local ins = {extra_inputs=table.move(alldeps, 1,#alldeps, 1,{})}
      local tfn,env = t.fn, t.env or ''
      if h.reference then tfn,env = t.reffn, t.refenv or env
      elseif h.annotations then tfn,env = t.annfn, t.annenv or env end

      env = env:gsub('%%(.)', repl)
      local args = (t.args or ''):gsub('%%(.)', repl)
      if h.redirect then args = args:gsub('%%o', h.redirect) end
      if i.grouped then args = args:gsub('%%f', i.fn)
      else table.insert(ins, i.fn) end
      if not t.grouped then table.insert(ins.extra_inputs, tfn) end

      local out = h.output:gsub('%%(.)', { t = t.id, i = i.id })
      local cmd = env..' '..h.cmd:gsub('%%(.)', {
        T=tfn, A=args, C=tfn..' '..args,
      })
      local name = '^'..(h.rebuild and '' or 'o')..' '
        ..h.id..' '..t.id..' '..i.id..' ^'

      if h.deps then tm(ins.extra_inputs, h.deps) end

      local outs = {out}
      if h.serialize then
        ti(ins.extra_inputs, serialend())
        lastsg = (lastsg or 0) + 1
        ti(outs, serialend())
      else ti(outs, cwd..'<s_init>') end

      local fakeaccess = ' stat '..i.fn..' '..tfn
        ..' >/dev/null && touch %o && LD_PRELOAD= '

      tup.rule(ins, name..fakeaccess..cmd, outs)
      table.insert(single, out)
      cnt = cnt + 1
      h.idx = cnt
    end
    table.insert(clusters, single)
    is[#clusters], ts[#clusters] = i, t
    end
  end end
  local allouts = {}
  for i,c in ipairs(clusters) do
    tm(allouts, post and (post(c, is[i], ts[i]) or {}) or c)
  end
  return allouts
end

function serialfinal()
  tup.rule(serialend(),
    '^o Serialization bridge^ touch %o',
    {'order_post', cwd..('<s_%d_post>'):format(sclass)})
end
