-- luacheck: std lua53, no global (Tup-Lua)

tup.include 'common.lua'

local cwd = tup.getcwd():gsub('[^/]$', '%0/')

alldeps = table.move(allbuilds, 1,#allbuilds,
  4, {cwd..'../external/lua/luaexec', cwd..'../inputs/<all>',
      cwd..'struct/<out>'})

structs = tup.glob(cwd..'struct/*.struct')
for i,s in ipairs(structs) do structs[i] = '-S '..s end
structs = table.concat(structs, ' ')

-- Inputs are collected and constructed in /inputs
tup.include '../inputs/inputs.lua'

-- List of tests to test with
tests = {}
local function add_test(base)
  if base.fnstem then
    local pre = ''
    if base.mpirun then pre = '`pwd`/' end
    base.modes = {
      [false] = pre..cwd..'../latest/'..base.fnstem,
      ann = pre..cwd..'../annotated/'..base.fnstem,
      ref = pre..cwd..'../reference/'..base.fnstem,
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
  inkind = 'binary',
  fnstem = 'hpctoolkit/install/bin/hpcstruct.real',
  args = '-j%T --jobs-symtab %T -o %o %f',
  outclean = [=[sed -e 's/i="[[:digit:]]\+"/i="NNNNN"/g' %f > %o]=],
}
add_test { id = 'unstrip', size = 2, grouped = true, cfg = '!UNSTRIP',
  inkind = 'binary',
  fnstem = 'dyninst/install/bin/unstrip',
  env = 'OMP_NUM_THREADS=%T', args = '-f %f -o %o',
  input = 'strip -So %o %f', outclean = 'nm -a %f > %o',
}
add_test { id = 'micro-symtab', size = 1, grouped = true, cfg = '!MICRO',
  inkind = 'binary',
  fnstem = 'micro/micro-symtab',
  env = 'OMP_NUM_THREADS=%T', args = '%f',
  nooutput = true,
}
add_test { id = 'micro-parse', size = 1, grouped = true, cfg = '!MICRO',
  inkind = 'binary',
  fnstem = 'micro/micro-parse',
  env = 'OMP_NUM_THREADS=%T', args = '%f',
  nooutput = true,
}
add_test { id = 'hpcprof', size = 3, grouped = true, cfg = 'HPCPROF',
  inkind = 'trace',
  fnstem = 'hpctoolkit/install/bin/hpcprof.real',
  tartrans = true,
  env = 'OMP_NUM_THREADS=%T', args = '--metric-db yes -o @@%o @%f',
  outclean = {
    inputs={extra_inputs={cwd..'../external/lua/luaexec'}},
    command='tar xOf %f ./experiment.xml | '..cwd..'../external/lua/luaexec '
      ..cwd..'profclean.lua '..cwd..' %o',
  },
}
add_test { id = 'hpcprof-struct', size = 3, grouped = true, cfg = 'HPCPROF',
  inkind = 'trace',
  fnstem = 'hpctoolkit/install/bin/hpcprof.real',
  tartrans = true,
  env = 'OMP_NUM_THREADS=%T', args = structs..' --metric-db yes -o @@%o @%f',
  outclean = {
    inputs={extra_inputs={cwd..'../external/lua/luaexec'}},
    command='tar xOf %f ./experiment.xml | '..cwd..'../external/lua/luaexec '
      ..cwd..'profclean.lua '..cwd..' %o',
  },
}
add_test { id = 'hpcprofmock', size = 1, grouped = true, cfg = '!HPCPROFMOCK',
  inkind = 'trace',
  fnstem = 'hpctoolkit/install/bin/hpcprofmock.real', nofn = {'ref'},
  tartrans = true,
  env = 'OMP_NUM_THREADS=%T', args = '@%f > %o',
}
add_test { id = 'hpcprof-mpi', size = 3, grouped = true, cfg = 'HPCPROF_MPI',
  inkind = 'trace',
  fnstem = 'hpctoolkit/install/bin/hpcprof-mpi.real',
  mpirun = true, tartrans = true,
  env = 'OMP_NUM_THREADS=%T', args = '-o @@%o @%f',
  outclean = {
    inputs={extra_inputs={cwd..'../external/lua/luaexec'}},
    command='tar xOf %f ./experiment.xml | '..cwd..'../external/lua/luaexec '
      ..cwd..'profclean.lua '..cwd..' %o',
  },
}
add_test { id = 'hpcprof-mpi-struct', size = 3, grouped = true, cfg = 'HPCPROF_MPI',
  inkind = 'trace',
  fnstem = 'hpctoolkit/install/bin/hpcprof-mpi.real',
  mpirun = true, tartrans = true,
  env = 'OMP_NUM_THREADS=%T', args = structs..' -o @@%o @%f',
  outclean = {
    inputs={extra_inputs={cwd..'../external/lua/luaexec'}},
    command='tar xOf %f ./experiment.xml | '..cwd..'../external/lua/luaexec '
      ..cwd..'profclean.lua '..cwd..' %o',
  },
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
  for _,i in ipairs(inputs) do for _,t in ipairs(tests) do if t.inkind == i.kind then
    local single = {}
    for _,h in ipairs{harness(i, t)} do
      local threads = h.threads or 1
      local mpirun,env = '',''
      if t.mpirun then
        local ranks
        if threads <= 4 then ranks,threads = threads, 1
        else ranks,threads = math.floor(threads/4), 4 end
        mpirun = tup.getconfig 'MPIRUN'
        if mpirun == '' then mpirun = 'mpirun' end
        env = 'TUP_PGID=`ps -o pgid $$ | tail -n1` TUP_CWD="`pwd`"'
        mpirun = mpirun..' -H localhost -wd / -oversubscribe -np '..ranks
          ..[[ perl -e '$o=getpgrp(0); setpgrp(0,$ENV{"TUP_PGID"});]]
          ..[[ chdir($ENV{"TUP_CWD"}); system(@ARGV)==0]]
          ..[[ or print "$ARGV[0]: $?: $!"; setpgrp(0,$o)']]
      end
      local tartrans = ''
      if t.tartrans or h.tartrans then
        tartrans = cwd..'../tartrans.sh'
      end

      local repl = {
        T = ('%d'):format(threads),
      }
      local ins = {extra_inputs=table.move(alldeps, 1,#alldeps, 1,{})}
      local tfn = assert(t.modes[h.mode or false])
      env = env..' '..(t.env or '')..' '..(h.env or '')

      local outs = {nil, '^^/tmp/tmp\\.', extra_outputs={}}
      env = env:gsub('%%(.)', repl)
      if tup.getconfig 'TMPDIR' ~= '' then
        env = 'TMPDIR="'..tup.getconfig 'TMPDIR'..'" '..env
        table.insert(outs, '^^'..subp.lexec('realpath "'..tup.getconfig 'TMPDIR'..'"'))
      end
      local args = (t.args or ''):gsub('%%(.)', repl)
      if h.redirect then args = args:gsub('%%o', h.redirect) end
      if not t.grouped then table.insert(ins.extra_inputs, tfn) end

      local ifn = assert(i.modes[h.mode or false])
      if i.grouped then args = args:gsub('%%f', ifn)
      else table.insert(ins, ifn) end

      local out = h.output:gsub('%%(.)', { t = t.id:gsub('/','.'), i = i.id:gsub('/','.') })
      local cmd = env..' '..tartrans..' '..mpirun..' '..h.cmd:gsub('%%(.)', {
        T=tfn, A=args, C=tfn..' '..args,
      })
      local name = '^'..(h.rebuild and '' or 'o')..' '
        ..h.id..' '..t.id..' '..i.id..' ^'

      if h.deps then tm(ins.extra_inputs, h.deps) end

      local fakeaccess = ''

      outs[1] = out
      if h.serialize or t.mpirun then
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
  end end end
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
