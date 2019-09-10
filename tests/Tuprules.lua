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

function ruleif(ins, ...)
  if #ins > 0 then tup.rule(ins, ...) end
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

alldeps = {}
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

-- List of available input transformations
intrans = {
  -- Makes a tarball with the output from hpcrun
  hpcrun = { grouped = true, cmd = cwd..'tartrans.sh '
    ..cwd..'../reference/hpctoolkit/install/bin/hpcrun.real '
      ..'-o @@%o -t -e REALTIME@100 '
    ..cwd..'../latest/hpctoolkit/install/bin/hpcstruct.real '
      ..'-o /dev/null -j 8 %f',
  },
}

-- List of tests to test with
tests = {}
local function add_test(base)
  if base.fnstem then
    base.modes = {
      [false] = cwd..'../latest/'..base.fnstem,
      ann = cwd..'../annotated/'..base.fnstem,
      ref = cwd..'../reference/'..base.fnstem,
    }
    if base.nofn then
      for _,k in ipairs(base.nofn) do base.modes[k] = nil end
      base.nofn = nil
    end
    base.fnstem = nil
  end
  if base.cfg then
    local default = true
    if base.cfg:find '^!' then default,base.cfg = false, base.cfg:sub(2) end
    if not enabled('TEST_'..base.cfg, default) then return end
    base.cfg = nil
  end
  table.insert(tests, base)
end

add_test { id = 'hpcstruct', size = 3, grouped = true, cfg = 'HPCSTRUCT',
  fnstem = 'hpctoolkit/install/bin/hpcstruct.real',
  args = '-j%T --jobs-symtab %T -o %o %f',
  outclean = [=[sed -e 's/i="[[:digit:]]\+"/i="NNNNN"/g' %f > %o]=],
}
add_test { id = 'unstrip', size = 2, grouped = true, cfg = '!UNSTRIP',
  env = 'OMP_NUM_THREADS=%T',
  fnstem = 'dyninst/install/bin/unstrip',
  args = '-f %f -o %o',
  input = 'strip -So %o %f',
  outclean = 'nm -a %f > %o',
}
add_test { id = 'micro-symtab', size = 1, grouped = true, cfg = 'MICRO',
  env = 'OMP_NUM_THREADS=%T',
  fnstem = 'micro/micro-symtab',
  args = '%f',
  nooutput = true,
}
add_test { id = 'micro-parse', size = 1, grouped = true, cfg = 'MICRO',
  env = 'OMP_NUM_THREADS=%T',
  fnstem = 'micro/micro-parse',
  args = '%f',
  nooutput = true,
}
add_test { id = 'hpcprof', size = 3, grouped = true, cfg = '!HPCPROF',
  env = 'OMP_NUM_THREADS=%T '..cwd..'tartrans.sh',
  fnstem = 'hpctoolkit/install/bin/hpcprof.real',
  args = '-o @@%o @%f', inputtrans = 'hpcrun',
  outclean = 'tar xOf %f ./experiment.xml | sed '
    ..[=[-e 's/\(db-m[ia][nx]-time\)="[[:digit:]]\+"/\1="TTTT"/g' ]=]
    ..[=[-e 's/i="[[:digit:]]\+"/i="NNNN"/g' ]=]
    ..' > %o',
}
add_test { id = 'hpcprofmock', size = 1, grouped = true, cfg = 'HPCPROFMOCK',
  env = 'OMP_NUM_THREADS=%T '..cwd..'tartrans.sh',
  fnstem = 'hpctoolkit/install/bin/hpcprofmock.real', nofn = {'ref'},
  args = '@%f > %o', inputtrans = 'hpcrun',
}

local ti,tm = table.insert,tup.append_table

local lastsg
function minihash(s)
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
      local tfn,env = assert(t.modes[h.mode or false]), t.env or ''

      env = env:gsub('%%(.)', repl)
      local args = (t.args or ''):gsub('%%(.)', repl)
      if h.redirect then args = args:gsub('%%o', h.redirect) end
      if not t.grouped then table.insert(ins.extra_inputs, tfn) end

      if t.inputtrans then
        table.insert(ins.extra_inputs, cwd..'<inputs>')
        args = args:gsub('%%f', cwd..'inputs/'..minihash(t.inputtrans..i.id))
      elseif i.grouped then args = args:gsub('%%f', i.fn)
      else table.insert(ins, i.fn) end

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
