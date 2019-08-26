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

if not ({['']=true, ['0']=true})[tostring(tup.getconfig 'MAX_THREADS')] then
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
  '../latest/elfutils', '../latest/dyninst', '../annotated/dyninst',
  '../latest/hpctoolkit', '../annotated/hpctoolkit', '../reference/elfutils',
  '../reference/dyninst', '../reference/hpctoolkit', '../annotated/elfutils',
  '../reference/micro', '../latest/micro', '../annotated/micro',
  '../latest/testsuite',
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
if enabled('ONLY_EXTERNAL', false) then inputs = {} end
for _,s in ipairs{'1', '2', '3', 'huge'} do
  local sz = tonumber(s) or math.huge
  for _,f in ipairs(tup.glob(cwd..'/../inputs/'..s..'/*')) do
    local id = f:match '[^/]+$'
    if id ~= '.gitignore' then table.insert(inputs, {id=id, fn=f, size=sz}) end
  end
end
table.sort(inputs, function(a,b) return a.id < b.id end)

-- List of tests to test with
tests = {
  { id = 'hpcstruct',
    size = 3, grouped = true,
    env = 'OMP_NUM_THREADS=%T',
    modes = {
      [false] = cwd..'../latest/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
      ann = cwd..'../annotated/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
      ref = cwd..'../reference/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    },
    args = '-j%T --jobs-symtab %T -o %o %f',
    outclean = [=[sed -e 's/i="[[:digit:]]\+"/i="NNNNN"/g' %f > %o]=],
  },
  -- { id = 'unstrip',
  --   size = 2, grouped = true,
  --   env = 'OMP_NUM_THREADS=%T',
  --   fn = cwd..'../latest/dyninst/install/bin/unstrip',
  --   annfn = cwd..'../annotated/dyninst/install/bin/unstrip',
  --   reffn = cwd..'../reference/dyninst/install/bin/unstrip',
  --   args = '-f %f -o %o',
  --   unstable = true,  -- TODO: outclean = 'nm -a ...',
  -- },
  { id = 'micro-symtab', nooutput = true,
    size = 1, grouped = true,
    env = 'OMP_NUM_THREADS=%T',
    modes = {
      [false] = cwd..'../latest/micro/micro-symtab',
      ann = cwd..'../annotated/micro/micro-symtab',
      ref = cwd..'../reference/micro/micro-symtab',
    },
    args = '%f',
  },
  { id = 'micro-parse', nooutput = true,
    size = 1, grouped = true,
    env = 'OMP_NUM_THREADS=%T',
    modes = {
      [false] = cwd..'../latest/micro/micro-parse',
      ann = cwd..'../annotated/micro/micro-parse',
      ref = cwd..'../reference/micro/micro-parse',
    },
    args = '%f',
  },
}

local ti,tm = table.insert,tup.append_table

local lastsg
local function minihash(s)
  local bs = { [0] =
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
    'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
    'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
    'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','-',
  }

  local byte, rep = string.byte, string.rep
  local pad = 2 - ((#s-1) % 3)
  s = (s..rep('\0', pad)):gsub("...", function(cs)
    local a, b, c = byte(cs, 1, 3)
    return bs[a>>2] .. bs[(a&3)<<4|b>>4] .. bs[(b&15)<<2|c>>6] .. bs[c&63]
  end)
  return s:sub(1, #s-pad) .. rep('=', pad)
end
function serialend()
  return lastsg and 'order/'..lastsg or
    (sclass == 1 and cwd..'<pre>' or cwd..('<s_%d>'):format(sclass-1))
end

-- The actual rule-creation command, that handles any little oddities
function forall(harness, post)
  local cnt = 0
  local clusters, is, ts = {},{},{}
  for _,i in ipairs(inputs) do for _,t in ipairs(tests) do
    local single = {}
    for _,h in ipairs{harness(i, t)} do
      local repl = {
        T = ('%d'):format(h.threads or 1),
      }
      local ins = {extra_inputs=table.move(alldeps, 1,#alldeps, 1,{})}
      local tfn,env = t.modes[false], t.env or ''
      if h.mode then tfn = assert(t.modes[h.mode]) end

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

      local fakeaccess = ''

      local outs = {out, '^\\.hpctrace$', '^\\.hpcrun$', extra_outputs={}}
      if h.serialize then
        ti(ins.extra_inputs, serialend())
        lastsg = minihash(name)
        ti(outs.extra_outputs, serialend())
        fakeaccess = 'touch '..serialend()..' && '..fakeaccess
      else ti(outs, cwd..'<pre>') end

      if h.fakeout then fakeaccess = 'touch %o && '..fakeaccess end

      tup.rule(ins, name..fakeaccess..cmd, outs)
      table.insert(single, out)
      cnt = cnt + 1
      h.idx = cnt
    end
    table.insert(clusters, single)
    is[#clusters], ts[#clusters] = i, t
    end
  end
  local allouts = {}
  for i,c in ipairs(clusters) do
    tm(allouts, post and (post(c, is[i], ts[i]) or {}) or c)
  end
  return allouts
end

function serialpost() return '<post>' end

function serialfinal()
  tup.rule({serialend(), serialpost()},
    '^o Serialization bridge^ touch %o',
    {'order_post', (cwd..'<s_%d>'):format(sclass)})
end
