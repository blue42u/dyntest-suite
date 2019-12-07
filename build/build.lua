-- luacheck: std lua53, new globals tup serpent subp

tup.include '../external/serpent.lua'

-- Unmagic the magic characters within s, for stitching together patterns.
local function unmagic(s)
  return (s:gsub('[]^$()%%.[*+?-]', '%%%0'))
end

-- Command line argument parser, similar to getopt but better. Option string:
--  ( <short flag (1-char)>[/<long flag>] | <long flag> ) [,:;]
-- Where , means no argument, : means argument, and ; "optional" argument.
-- Handlers are indexed by long or short flag, and treated like gsub with
-- capture 1 being the argument and capture 2 the prefix (flag with matching space).
-- Special keys [true] and [false] are for the command word and positional args.
local function getopt(str, opts, handlers)
  -- First parse out what flags are available.
  local flags,types = {},{}
  for s,sep,l,t in opts:gmatch '(.)(/?)(.-)([,:;])' do
    if sep == '' then
      if l == '' then l = nil else s,l = nil,s..l end
    end
    assert(not l or #l > 1, 'Too short a long option!')
    assert(s or l, 'Bad optstring!')
    assert(s ~= '-', 'Bad short option!')
    assert(not l or l:sub(1,1) ~= '-', 'Bad long option!')
    if s then flags[s] = l or s end
    if l then flags[l] = l or s end
    types[l or s] = t
  end

  -- Next iteratively fold any string-like structures into magic characters.
  local substrs = {}
  local function substr(s)
    substrs[#substrs+1] = s
    local id = ('\0%d\0'):format(#substrs)
    substrs[id] = s
    return id
  end
  repeat local done = true
    str = str:gsub('([^\\])([`"\'])(.*)', function(p,q,rest)
      local s,extra = rest:match('^(.-[^\\])'..q..'(.*)')
      if not s then
        -- Check that its not just empty
        if rest:sub(1,1) == q then s,extra = '', rest:sub(2)
        else error('Unfinished quoted string in `'..str..'`!') end
      end
      s = s:gsub('\\'..q, q)  -- Any escaped chars can live unescaped
      if q ~= '`' then q = '' end  -- Normal strings will be folded together
      done = false
      return p..substr(q..s..q)..extra
    end)
  until done

  -- Any remaining quotes are escaped, wipe off the backslashes
  str = str:gsub('\\([`"\'])', '%1')

  -- Function to handle arguments and construct bits.
  local bits = {}
  local function handle(flag, pre, oneword, arg)
    local function ba(x) table.move(x, 1,#x, #bits+1, bits) end
    local function pass() if oneword then ba{pre..arg} else ba{pre, arg} end end
    local h = handlers[flag]
    if h == nil or h == true then pass()  -- Pass through with no fuss
    elseif h == false then return  -- Skip argument
    elseif type(h) == 'function' then
      local x = {h(arg, pre)}
      if #x == 0 then pass()
      elseif x[1] == false then return
      else
        for i,y in ipairs(x) do
          assert(type(y) == 'string')
          if y == '?' then
            if oneword then x[i],x[i+1] = '', pre..x[i+1]
            else x[i] = pre end
          end
        end
        local i = 1
        repeat
          if x[i] == '' then table.remove(x,i) else i = i + 1 end
        until not x[i]
        ba(x)
      end
    else error('Unable to handle handler '..tostring(h)) end
  end

  -- Now work through each word and decide what to do with it.
  local cur,cpre,first = nil,nil,true
  for w in str:gmatch '[%g\0]+' do
    repeat local cnt
      w,cnt = w:gsub('\0%d+\0', substrs)
    until cnt == 0
    local q = w:match '^["\']'
    if q and w:find(q..'$') then w = w:gsub('^'..q, ''):gsub(q..'$', '') end
    if w:sub(1,1) == '-' then  -- Option argument
      if flags[w:sub(2,2)] then  -- Short option
        local f = flags[w:sub(2,2)]
        if #w > 2 and types[f] == ',' then error('Argument given to non-argument flag: '..w) end
        if #w == 2 and types[f] == ':' then  -- Argument in next word
          cur,cpre = f, '-'..f
        else  -- Argument (if present) in this word
          handle(f, w:sub(1,2), true, w:sub(3))
        end
      else  -- Must be a long option
        local p,f,e,a = w:match '^(%-%-?)([^=]+)(=?)(.*)'
        f = assert(flags[f], 'Invalid option '..f)
        if e == '=' or types[f] ~= ':' then  -- Argument given in this word
          if types[f] == ',' and e ~= '' then
            error('Argument given to non-argument flag: '..w)
          end
          handle(f, p..f..e, true, a)
        else cur,cpre = f,p..f end -- Argument in next word
      end
    elseif w:find '^>' then  -- Output redirection
      assert(not first)
      if #w == 1 then cur,cpre = '>', '>'
      else handle('>', '>', true, w:sub(2)) end
    elseif w:find '^<' then  -- Input redirection
      assert(not first)
      if #w == 1 then cur,cpre = '<', '<'
      else handle('<', '<', true, w:sub(2)) end
    else  -- Non-option argument
      if cur then handle(cur, cpre, false, w); cur = nil  -- Argument to a flag
      else handle(first, '', false, w); first = false end  -- Positional arg
    end
  end
  return bits
end

-- Simple path munching function, takes a path and resolves any ../
local function canonicalize(p, cwd)
  local cbits = {}
  for b in (cwd or ''):gmatch '[^/]+' do table.insert(cbits, b) end
  for i=1,#cbits do  -- Reverse the table
    local j = #cbits-i+1
    if i >= j then break end
    cbits[i],cbits[j] = cbits[j],cbits[i]
  end
  local ups,bits = 0,{}
  for b in p:gmatch '[^/]+' do
    if b == '..' then
      if #bits == 0 then ups = ups + 1 else table.remove(bits) end
    elseif b ~= '.' then  -- Skip over just .
      if cbits[ups] == b then ups = ups - 1 -- Fold a ../here
      else table.insert(bits, b) end
    end
  end
  local abs = p:sub(1,1) == '/' and ups == 0 and '/' or ''
  return abs..('../'):rep(ups)..table.concat(bits, '/')
end
local function dir(path) return path:gsub('([^/])/*$', '%1/') end
local topcwd = dir(tup.getcwd())
local topdir = dir(subp.lexec 'pwd')

-- The main script for building things. Handles everything from CMake to Libtool
-- and the antiparallelism in Elfutils. Wrapped as a function to allow usage
-- in multiple locations with varying options.
function build(opts)  -- luacheck: new globals build

-- Step 0: Gather info about where all the files actually are from here.
local fullsrcdir = dir(opts.srcdir)
local srcdir = dir(canonicalize(topcwd..'../'..fullsrcdir))
local realsrcdir = topdir..fullsrcdir
local fullbuilddir = dir(opts.builddir)
local realbuilddir = topdir..fullbuilddir

local exdeps,exhandled,transforms,runpath = {},{},{},{realbuilddir..'install/lib'}
local cppflags,cxxflags,ldflags = {},{},{}
local cfgflags = {}
for f in opts.cfgflags:gmatch '%g+' do
  f = f:gsub('@@/', topdir):gsub('@([^@]+)@', function(ed)
    local ret,raw = true,false
    if ed:sub(1,1) == '!' then ret,ed = false,ed:sub(2) end
    if ed:sub(1,1) == '!' then raw,ed = true,ed:sub(2)
    elseif ed:sub(1,2) == 'I!' then raw,ed = 'I',ed:sub(3)
    elseif ed:sub(1,2) == 'L!' then raw,ed = 'L',ed:sub(3)
    elseif ed:sub(1,3) == 'CF!' then raw,ed = 'CF',ed:sub(4)
    elseif ed:sub(1,5) == 'CXXF!' then raw,ed = 'CXXF',ed:sub(6)
    elseif ed:sub(1,3) == 'LF!' then raw,ed = 'LF',ed:sub(4) end
    local path = raw and '/'..dir(ed)
      or ed:sub(1,1) ~= '/' and dir(ed)
      or dir(canonicalize(topcwd..'..'..ed))
    local rpath = raw and dir(ed)
      or ed:sub(1,1) == '/' and dir(topdir..ed:sub(2))
      or dir(canonicalize(realbuilddir..ed))
    if not exhandled[path] then
      if raw then
        if raw == true or raw == 'L' then table.insert(runpath, rpath) end
        if raw == 'I' then table.insert(cppflags, '-I'..rpath)
        elseif raw == 'L' then table.insert(ldflags, '-L'..rpath)
        elseif raw == 'CF' then table.insert(cppflags, ed)
        elseif raw == 'CXXF' then table.insert(cxxflags, ed)
        elseif raw == 'LF' then table.insert(ldflags, ed) end
      else
        table.insert(exdeps, path..'<build>')
        transforms[rpath..'dummy'] = path..'install'
        table.insert(runpath, rpath..'install/lib')
      end
      exhandled[path] = true
    end
    return ret and rpath..'dummy' or ''
  end)
  table.insert(cfgflags, f)
end
runpath = table.concat(runpath, ':')
cxxflags = table.move(cxxflags,1,#cxxflags,
  #cppflags+1,table.move(cppflags,1,#cppflags,1,{}))
transforms[realsrcdir] = srcdir
transforms[realbuilddir] = ''

-- Helper for interpreting tup.glob output, at least for what we do.
local function glob(s)
  local ok, x = pcall(tup.glob, s)
  return ok and #x > 0 and x
end

-- We're going to be dealing with lots of paths, this function extracts all the
-- info you ever wanted about a path, and a number of translations into
-- absolute or relative versions.
local function path(p, cwd)
  if p:sub(1,1) ~= '/' then  -- Path relative to builddir/cwd, make absolute.
    p = realbuilddir..dir(cwd or '')..p
  end
  p = canonicalize(p)
  local o = {absolute = p}
  for from,to in pairs(transforms) do  -- Try to transform it.
    local r,s
    if dir(p) == from then r,s = to,''
    elseif p:sub(1,#from) == from then r,s = to,p:sub(#from+1)
    end
    if r then
      if o.root then error(o.root..' & '..to..' match '..p) end
      o.root,o.stem = r,s
      o.path = o.root..o.stem
      if to == srcdir then o.source = true
      elseif to == '' then o.build = true
      else o.external = true end
    end
  end
  return o
end

-- We're going to use a temporary directory, this xpcall ensures we delete it.
local tmpdir, docleansrcdir, finalerror
local function finalize()
  if tmpdir then subp.exec('rm -rf '..tmpdir) end
  if docleansrcdir then subp.exec("cd '"..realsrcdir.."' && git clean -fX") end
end
xpcall(function()
tmpdir = subp.lexec 'mktemp -d':gsub('([^/])/*$', '%1/')
transforms[tmpdir] = ''  -- tmpdir acts as the build directory too

-- Helper for handling boolean config values
local function cfgbool(n, d)
  local s = string.lower(tup.getconfig(n))
  if s == '' then return d
  elseif s == 'y' then return true
  elseif s == 'n' then return false
  end
  error('CONFIG_'..n..' must be y/n (default is '..(d and 'y' or 'n')..')')
end
local function c_slines(...)
  local s = subp.shell(...)
  if cfgbool 'DEBUG_CONFIGURE' then print('CFG:', s) end
  return subp.plines(s)
end

-- Step 1: Figure out the build system in use and let it do its thing.
if glob(srcdir..'configure.ac') then  -- Its an automake thing
  local mpicc = tup.getconfig 'MPICC'
  if mpicc == '' then mpicc = 'mpicc' end
  local mpicxx = tup.getconfig 'MPICXX'
  if mpicxx == '' then mpicxx = 'mpic++' end
  docleansrcdir = true
  local env = {
    PATH = topdir..'/build/bin:?',
    AUTOM4TE = topdir..'/build/autom4te-no-cache',
    REALLDD = subp.lexec 'which ldd',
    CFLAGS = '-g', CXXFLAGS = '-g',
    MPICC=mpicc, MPICXX=mpicxx,
  }
  for l in c_slines({'autoreconf', '-fis', fullsrcdir, onlyout=true, env=env}) do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
  -- Run configure too while everything is arranged accordingly
  for l in c_slines({'cd', tmpdir}, {env=env, realsrcdir..'configure',
    '--prefix='..realbuilddir..'install',
    '--disable-dependency-tracking',
    cfgflags, onlyout=true}) do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
elseif glob(srcdir..'CMakeLists.txt') then  -- Negligably nicer CMake thing
  for l in c_slines({'cd', tmpdir}, {'cmake', '-G', 'Unix Makefiles', cfgflags,
    '-DCMAKE_INSTALL_PREFIX='..realbuilddir..'install',
    '-DCMAKE_BUILD_TYPE=RelWithDebInfo',
    '-DCMAKE_MODULE_PATH='..topdir..'build',
    realsrcdir}) do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
else error("Unable to determine build system!") end

-- Step 2: Have GNU make cough up its own database with all the rules, and
-- construct a global view of the world with all the bits.
local makevarpatt = '[%w_<>@.?%%^*+-]+'
local parsemakecache = {}
local function parsemakefile(fn, cwd)
  cwd = dir(cwd or '')
  if parsemakecache[cwd..fn] then
    assert(parsemakecache[cwd..fn].cwd == cwd,
      'Makefile '..cwd..fn..' parsed under different working dirs!')
    return parsemakecache[cwd..fn]
  end
  local ruleset = {templates={}, normal={}, cwd=cwd}
  parsemakecache[cwd..fn] = ruleset

  -- A simple single-state machine for parsing.
  local state = 'preamble'
  local vars,cur = {},nil
  for l in subp.slines{
    {{'cat', tmpdir..cwd..fn}, {'printf', 'dummyZXZ:\\n\\n'}},
    {'env','-i', 'make', '-C', tmpdir..cwd, '-pqsrRf-', 'dummyZXZ', reerr=false}
  } do
    if state == 'preamble' then
      if l:find '^#%s*Variables$' then state = 'vars' end
      assert(l:sub(1,1) == '#' or #l == 0, l)
    elseif state == 'vars' then
      if l:find '^#%s*Implicit Rules' then state = 'outsiderule' else
        if #l > 0 and l:sub(1,1) ~= '#' then
          local k,v = l:match('^('..makevarpatt..')%s*:?=%s*(.*)$')
          assert(k and v, l)
          vars[k] = v
        end
      end
    elseif state == 'outsiderule' then
      if l:find '^[^#%s].*:' then
        state = 'rulepreamble'
        cur = {vars = vars, cwd = cwd}
        cur.outs, cur.deps = l:match '^(.-):%s*(.*)$'
        assert(not cur.outs:find '%$' and not cur.deps:find '%$', l)
        local x = {}
        for p in cur.outs:gmatch '%g+' do
          if not cur.target then cur.target = p end
          p = path(p, cwd)
          if not p.path then x = false; break end
          if p.path:find '%%' then cur.implicit = true end
          table.insert(x, p)
        end
        if not x then cur = nil else
          cur.outs = x
          local y = {}
          for p in cur.deps:gmatch '%g+' do
            p = path(p, cwd)
            if p.path then table.insert(y, p) end
          end
          cur.deps = y
        end
      else assert(#l == 0 or l:sub(1,1) == '#', l) end
    elseif state == 'rulepreamble' then
      if l:sub(1,1) ~= '#' then state = 'rule' end
    end
    if state == 'rule' then
      if #l == 0 then state = 'outsiderule' end
      if cur then
        if #l == 0 then  -- Rule end
          if cur.implicit then  -- Implicit rule
            local rs = ruleset.templates
            for _,p in ipairs(cur.outs) do
              p = p.path
              if not rs[p] then rs[p] = {} end
              rs[p][cur] = true
            end
          else  -- Normal rule, file output (in theory)
            local rs = ruleset.normal
            for _,p in ipairs(cur.outs) do
              p = p.path
              if rs[p] then  -- Another rule already placed down.
                if #rs[p] == 0 then  -- Other rule is dep-only. Take its deps.
                  table.move(rs[p].deps, 1,#rs[p].deps, #cur.deps+1, cur.deps)
                  rs[p] = cur
                elseif #cur == 0 then  -- I'm dep-only, append my new deps
                  table.move(cur.deps, 1,#cur.deps, #rs[p].deps+1, rs[p].deps)
                else  -- Two recipes for the same file, error.
                  print(table.unpack(rs[p].outs))
                  print(table.unpack(rs[p]))
                  print(table.unpack(cur.outs))
                  print(table.unpack(cur))
                  error(cwd..'| '..p)
                end
              else rs[p] = cur end
            end
          end
        elseif l:find '%g' then  -- Recipe line
          assert(l:sub(1,1) == '\t', l)
          if #cur > 0 and cur[#cur]:sub(-1) == '\\' then
            cur[#cur] = cur[#cur]:sub(1,-2):gsub('%s*$', '')
              ..' '..l:gsub('^%s*', '')
          else table.insert(cur, l:sub(2)) end
        end
      end
    end
  end
  return ruleset
end

-- Step 3: Hunt down the files that we need to generate, and find or construct
-- a rule to generate them. Also do some post-processing for expanding vars.
local madefiles = {}
local function findrule(fn, ruleset)
  local r = ruleset.normal[fn.path]
  if not r or #r == 0 then
    -- If its part of the externals, it exists already so just ignore it.
    if fn.external then return end

    -- If its from "out there", it really does exist already
    if not fn.source and not fn.build then return end

    -- If its a source file, check if it exists yet
    if fn.source and glob(fn.path) then return end

    -- If it looks like a build file, check whether its a temp file.
    if fn.build and subp.stestexec{'stat', tmpdir..fn.stem, onlyout=true, reout=false} then
      return nil, 'tmpdir'
    end

    -- If it looks like a build file, check if its actually a source file
    if fn.build and not fn.path:find 'CMakeFiles/' and glob(srcdir..fn.stem) then
      return nil, 'source'
    end

    -- Try hunting down an implicit rule to handle this one. Since this is a
    -- "use-what-works" recursive search, the logic is bottled in its own func.
    local function search(f)
      local final,fstem
      for pat in pairs(ruleset.templates) do
        local p = '^'..unmagic(pat:gsub('%%', '!:!')):gsub('!:!', '(.+)')..'$'
        local m = f.path:match(p)
        if m then
          if final then error(pat..' & '..final..' match '..f.path) end
          final,fstem = pat,m
        end
      end
      if final then
        local irs = ruleset.templates[final]
        local any = false
        for ir in pairs(irs) do if #ir > 0 then any = true
          local ok = true
          for _,d in ipairs(ir.deps) do
            do
              local nd = {}
              for k,v in pairs(d) do nd[k] = v end
              nd.stem = d.stem:gsub('%%', fstem)
              nd.path = nd.root..nd.stem
              d = nd
            end
            if d.external then ok = true
            elseif d.source and (glob(d.path) or glob(d.stem)) then ok = true
            elseif d.build and (glob(srcdir..d.stem)) then ok = true
            elseif ruleset.normal[d.path] then ok = true
            elseif madefiles[d.path] then ok = true
            elseif search(d) then ok = true
            else ok = false; break end
          end
          if ok then return ir,fstem end
        end end
        assert(not any, 'No successful implicit rule for '..f.path)
      end
    end
    local ir,istem = search(fn)
    if ir then  -- Search successful, copy over the relevent info
      r = r or {outs = {}, vars = ir.vars, cwd = ir.cwd}
      for i,o in ipairs(ir.outs) do
        do
          local n = {}
          for k,v in pairs(o) do n[k] = v end
          n.stem = o.stem:gsub('%%', istem)
          n.path = n.root..n.stem
          o = n
        end
        if r.outs[i] then assert(r.outs[i].path == o.path) end
        r.outs[i] = o
      end
      local exds = r.deps or {}
      r.deps = {}
      for _,d in ipairs(ir.deps) do
        do
          local n = {}
          for k,v in pairs(d) do n[k] = v end
          n.stem = d.stem:gsub('%%', istem)
          n.path = n.root..n.stem
          d = n
        end
        table.insert(r.deps, d)
      end
      table.move(exds, 1,#exds, #r.deps+1, r.deps)
      r.stem = istem
      table.move(ir, 1,#ir, 1,r)
    end

    -- Otherwise, its probably a pseudo-phony.
    assert(r, 'No rule to generate '..(fn.path or fn.absolute)..'!')
  end
  if r.found then return r end  -- Don't duplicate work if possible.
  r.found = true

  -- Expansion is tricky, the magic character is $, but () and {} can group.
  -- So we take an approach that is simple although not quite correct.
  local funcs = {}
  local function expand(s, vs)
    assert(s and vs, s)
    local bits,init = {},1
    repeat
      local i = s:find('%$', init)
      if i then
        table.insert(bits, s:sub(init, i-1))
        local q = s:sub(i+1,i+1)
        if q == '$' then  -- Escape for $
          table.insert(bits, '$')
          init = i+2
        elseif q == '(' then  -- Start of $(...)
          local c
          c,init = s:match('^(%b())()', i+1)
          assert(c)
          c = c:sub(2,-2)  -- Strip ()
          if c:find '^[%w-]+%s' then  -- Function-style
            local f,a = c:match '^([%w-]+)%s+(.*)'
            local as,it = {}, 1
            repeat
              local x,e,ii
              as[#as+1] = ''
              repeat
                x,e,ii = a:match('^([^,(]*)(.?)()', it)
                as[#as] = as[#as]..x
                if e == '(' then
                  x,ii = a:match('^(%b())()', ii-1)
                  as[#as] = as[#as]..x
                end
                it = ii
              until e == ',' or e == ''
            until e == ''
            if not funcs[f] then
              for k,v in ipairs(as) do as[k] = ('%q'):format(v) end
              error('Unhandled function expansion: '..f..'('..table.concat(as, ', ')..')')
            end
            table.insert(bits, funcs[f](vs, table.unpack(as)))
          elseif c:find ':' then  -- Substitution style
            local v,a,b = c:match '([^:]+):(.*)=(.*)'
            assert(v and not a:find '%%', c)
            v = expand(v, vs)
            assert(v:find '^'..makevarpatt..'$', v)
            table.insert(bits, (expand(vs[v] or '', vs)
              :gsub('(%g+)'..unmagic(a), '%1'..b:gsub('%%', '%%%%'))))
          else  -- Variable style
            c = expand(c, vs)
            assert(c:find '^'..makevarpatt..'$', c)
            table.insert(bits, expand(vs[c] or '', vs))
          end
        elseif q == '{' then  -- Start of ${}
          local v
          v,init = s:match('^{([^}]+)}()', i+1)
          assert(v)
          table.insert(bits, expand(vs[v] or '', vs))
        else  -- Start of automatic variable
          local v
          v,init = s:match('^([@<*^?])()', i+1)
          assert(v, '"'..s..'" @'..(i+1))
          table.insert(bits, expand(vs[v] or '', vs))
        end
      else table.insert(bits, s:sub(init)) end
    until not i
    return table.concat(bits)
  end

  -- Function expansions
  funcs['if'] = function(vs, cond, ifstr, elsestr)
    return expand(expand(cond, vs):find '%g' and ifstr or elsestr or '', vs)
  end
  function funcs.notdir(vs, str) return expand(str, vs):match '[^/]+$' end
  funcs['filter-out'] = function(vs, ws, str)
    ws,str = expand(ws,vs), expand(str,vs)
    assert(not ws:find '%%')
    local words = {}
    for w in ws:gmatch '%g+' do words[w] = '' end
    return (str:gsub('%g+', words))
  end
  function funcs.addprefix(vs, pre, str)
    return (expand(str, vs):gsub('%g+', pre:gsub('%%','%%%%')..'%0'))
  end
  function funcs.patsubst(vs, patt, repl, str)
    if patt:find '%%' then
      patt,repl = unmagic(patt:gsub('%%', '(.*)')), repl:gsub('%%', '%%1')
    else
      patt,repl = '(%g+)'..unmagic(patt), '%1'..repl:gsub('%%', '%%%%')
    end
    return (expand(str, vs):gsub(patt, repl))
  end
  function funcs.shell(vs, cmd)  -- By far the hairiest and most sensitive, hack
    if cmd == 'cd $(srcdir);pwd' then return expand('$(srcdir)', vs)
    elseif cmd == 'pwd' then return './'..r.cwd
    elseif cmd == '$(AR) t ../libdwfl/libdwfl.a' then
      return 'XXX'
    elseif cmd == '$(AR) t ../libdwelf/libdwelf.a' then
      return 'XXX'
    elseif cmd == '$(AR) t ../libebl/libebl.a' then
      return 'XXX'
    elseif cmd == '$(AR) t ../backends/libebl_backends.a' then
      return 'XXX'
    elseif cmd == '$(AR) t ../libcpu/libcpu.a' then
      return 'XXX'
    else error('Unhandled shell: '..cmd) end
  end
  function funcs.call(_, cmd)
    if cmd == 'HPC_moveIfStaticallyLinked' then
      -- Expand to a magic that will be handled down below somewhere
      return '!;@MISL@;!'
    elseif cmd == 'copy-libs' then
      -- The copy of all the bits to the ext_libs directory. Skip for now.
      return '!;@CL@;!'
    elseif cmd == 'strip-debug' then
      -- Strip the debugging info off the files. Skip for now.
      return '!;@SD@;!'
    else error('Unhandled call: '..cmd) end
  end

  -- Now expand the recipe in a separate table for further reference!
  local x = {}
  for i,d in ipairs(r.deps) do x[i] = d.path end
  r.vars = setmetatable({
    ['@'] = r.outs[1].path, ['<'] = r.deps[1] and r.deps[1].path or '',
    ['*'] = r.stem or '', ['^'] = table.concat(x, ' '),
  }, {__index=r.vars})
  function r.expand(s) return expand(s, r.vars) end
  r.ex = {}
  for i,c in ipairs(r) do r.ex[i] = r.expand(c):gsub('^[@-]*', '') end

  return r
end

-- Step 4: For some file, analyze the rule that generates it and determine its
-- properties and figure out the core recipe command for translation.
local translations = {}
local function make(fn, ruleset)
  if madefiles[fn.path] then return madefiles[fn.path] end  -- Some are already done.
  local r,src = findrule(fn, ruleset)
  if src == 'source' then  -- Its actually a source file
    return {path = srcdir..fn.stem, original=fn.path}
  elseif src == 'tmpdir' then  -- Its actually an "external"
    return {path = fn.stem, external=true}
  end
  if not r then return fn end  -- We don't need to do anything.
  if r.made then return r.made end  -- Don't duplicate work if at all possible.
  local info = {path = fn.path, cwd = r.cwd}
  if fn.source then info.path = fn.stem end  -- Map source outputs to build

  -- First make sure all the deps have been made
  info.deps = {}
  for i,d in ipairs(r.deps) do info.deps[i] = make(d, ruleset) end

  -- Next go through and identify every command, and collect together some
  -- info to pass to the specific translator.
  local handled,printout = {}, cfgbool 'DEBUG_MAKE_TRANSLATION'
  for i,c in ipairs(r) do
    local ex = r.ex[i]
    local function check(tf, note, err)
      if not tf then handled[i],fn.error = note or 'error', err or '#'..i end
    end
    if c:find '$%(ACLOCAL%)' then handled[i] = 'Autotools: call to aclocal'
    elseif c:find '$%(AUTOHEADER%)' then handled[i] = 'Autotools: call to autoheader'
    elseif c:find '$%(AUTOCONF%)' then handled[i] = 'Autotools: call to autoconf'
    elseif c:find '$%(AUTOMAKE%)' then handled[i] = 'Autotools: call to autoconf'
    elseif c:find 'am%-%-refresh' then handled[i] = 'Autotools: refresh magic'
    elseif c:find '^@?$%(mkinstalldirs%)' then handled[i] = 'Autotools: install dir creation'
    elseif c:find '$%(SHELL%) %./config%.status' then
      handled[i] = 'Autotools: call to config.status'
    elseif c:find '^@?rm %-f' or ex:find '^rm %-f' then
      handled[i] = 'Make: force removal of file'
      check(not info.kind)
    elseif ex:find '!;@' then handled[i] = 'HPCToolkit: clever and annoying things'
    elseif c:find '^if test "$%(PACKAGE%)" = "gettext%-tools"' then
      handled[i] = 'Autotools: localization system update'
    elseif c:find '^if { if %(LC_ALL=C find %-%-version%)' then
      handled[i] = 'Autotools: localization system update'
    elseif c:find '^test ! %-f $%(DOMAIN%)%.po' then
      handled[i] = 'Autotools: localization system update'
    elseif c:find '^@catalogs=\'$%(CATALOGS%)\';' then
      handled[i] = 'Autotools: localization system install'
    elseif c == '@$(CHECK_MACRO_VERSION)' then
      handled[i] = 'Autotools: macro version check'
    elseif c == 'test ! -f $(srcdir)/$(DOMAIN).pot || test -z "$(GMOFILES)" '
      ..'|| $(MAKE) $(GMOFILES)' then
      handled[i] = 'Autotools: Gettext update initializer'
    elseif c == ([[@test ! -f $(srcdir)/$(DOMAIN).pot || { echo "touch stamp-po"
      && echo timestamp > stamp-poT && mv stamp-poT stamp-po; }]]):gsub('%s*\n%s*', ' ') then
      handled[i] = 'Autotools: Gettext timestamp miniscript'
    elseif c == 'touch $@' then handled[i] = 'Make: touch of output file'
    elseif c:find '^@?$%(MKDIR_P%)' then handled[i] = 'Make: dir creation'
    elseif ex:find '^:' then handled[i] = 'Make: clever do-nothing command'
    elseif ex:find '^[@-]*mkdir%s+%-p' then handled[i] = 'Make: dir creation'
    elseif c:find '^@?test %-f $@ ||' then
      handled[i] = 'Autotools: timestamp management'
      check(c:find 'stamp%-h1')
    elseif c:find '$%(CMAKE_COMMAND%)%s+%-E%s+cmake_link_script%s' then
      handled[i] = 'LD: CMake-style linking/archiving command'
      check(not info.kind)
      info.kind = 'cmakeld'
      local cd = c:match '^cd%s+(%g+)'
      if cd then info.cwd = dir(path(cd, '').path) end
      info.script = c:match 'cmake_link_script%s+(%g+)'
      info.ruleset = ruleset
    elseif c:find '$%(CMAKE_COMMAND%)%s+%-E%s+cmake_symlink_library%s' then
      handled[i] = 'CMake: Link command'
      check(info.kind == 'cmakeld')
      info.links = {}
      local last
      for w in c:match 'cmake_symlink_library%s+(.*)':gmatch '%g+' do
        if last then
          table.insert(info.links, {path(w, info.cwd).path, last})
        end
        last = w
      end
    elseif c:find '^@?$%(CMAKE_COMMAND%)' then
      if c:find '%-E cmake_progress_start' then handled[i] = 'CMake: progress bar markers'
      elseif c:find '%-%-check%-build%-system' then handled[i] = 'CMake: makefile regeneration'
      elseif c:find '%-E cmake_echo_color' then handled[i] = 'CMake: status message'
      elseif c:find '%-E touch_nocreate' then handled[i] = 'CMake: touch'
      elseif c:find '%-P %g+cmake_clean_target%.cmake' then
        handled[i] = 'CMake: Subproject clean'
      else printout = true end
    elseif c:find '^@?$%(MAKE%)' or c:find '^cd.*&&%s*$%(MAKE%)' then
      handled[i] = 'Make: recursive subcall'
      local mf,cd = 'Makefile', ex:match '^cd%s+(%g+)%s+&&'
      if cd then cd = dir(path(cd, r.cwd).path); info.cwd = cd end
      info.targets = {}
      getopt(ex:match '&&(.*)' or ex, 'no-print-directory,f:', {
        f = function(f) mf = f end,
        [false] = function(t) table.insert(info.targets, path(t, info.cwd)) end,
      })
      if #info.targets == 0 then info.targets[1] = path('all', info.cwd) end
      info.ruleset = parsemakefile(mf, info.cwd)
      check(info.kind == 'make' or not info.kind)
      info.kind = 'make'
    elseif c == ([[@fail=; if $(am__make_keepgoing); then failcom='fail=yes';
    else failcom='exit 1'; fi; dot_seen=no; target=`echo $@ | sed
    s/-recursive//`; case "$@" in distclean-* | maintainer-clean-*)
    list='$(DIST_SUBDIRS)' ;; *) list='$(SUBDIRS)' ;; esac; for subdir in
    $$list; do echo "Making $$target in $$subdir"; if test "$$subdir" = ".";
    then dot_seen=yes; local_target="$$target-am"; else local_target="$$target";
    fi; ($(am__cd) $$subdir && $(MAKE) $(AM_MAKEFLAGS) $$local_target) || eval
    $$failcom; done; if test "$$dot_seen" = "no"; then $(MAKE) $(AM_MAKEFLAGS)
    "$$target-am" || exit 1; fi; test -z "$$fail"]]):gsub('\n%s*', ' ') then
      handled[i] = '# Autotools: Subdir recursive make call'
      info.targets,info.rulesets = {},{}
      local t = fn.path:match '([^/]+)%-recursive$'
      assert(t, fn.path)
      for sd in r.expand '$(SUBDIRS)':gmatch '%g+' do
        assert(sd ~= '.')
        table.insert(info.targets, path(t, r.cwd..dir(sd)))
        table.insert(info.rulesets, parsemakefile('Makefile', r.cwd..dir(sd)))
      end
      table.insert(info.targets, path(t..'-am', r.cwd))
      table.insert(info.rulesets, ruleset)
      check(not info.kind)
      info.kind = 'make'
    elseif c == ([[$(AM_V_GEN)UNSTRIP=$(bindir)/`echo unstrip | sed
    '$(transform)'`; AR=$(bindir)/`echo ar | sed '$(transform)'`; sed -e
    "s,[@]UNSTRIP[@],$$UNSTRIP,g" -e "s,[@]AR[@],$$AR,g" -e
    "s%[@]PACKAGE_NAME[@]%$(PACKAGE_NAME)%g" -e
    "s%[@]PACKAGE_VERSION[@]%$(PACKAGE_VERSION)%g"
    $(srcdir)/make-debug-archive.in > $@.new]]):gsub('\n%s*', ' ') then
      handled[i] = 'Sed: Hardcoded Elfutils sed command'
      check(not info.kind)
      info.kind = 'sed'
      info.cmd = 'sed -e "s,[@]UNSTRIP[@],'..topdir..'install/bin/eu-unstrip,g"'
        ..' -e "s,[@]AR[@],'..topdir..'install/bin/eu-ar,g"'
        ..' -e "s%[@]PACKAGE_NAME[@]%'..r.expand '$(PACKAGE_NAME)'..'%g"'
        ..' -e "s%[@]PACKAGE_VERSION[@]%'..r.expand '$(PACKAGE_VERSION)'..'%g"'
        ..' '..info.deps[1].path..' > src/make-debug-archive.new'
    elseif c:find '^@list=' then
      handled[i] = 'Autotools: main install miniscript'
      check(not info.kind)
      info.kind,info.dstdir = 'install', dir(path(ex:match '"(.-)"').path)
    elseif c:find '^$%(INSTALL%g*%)' then
      handled[i] = 'Autotools: single install call'
      check(not info.kind); info.kind = 'install'
      getopt(ex, 'c,m:', {
        [false] = function(p)
          if not info.src then info.src = path(p, info.cwd).path
          else info.dst = path(p, '').path end
        end,
      })
      info.dstdir = info.dst:match '(.-)[^/]+$'
    elseif c:find '^$%(MYLATEX2MAN%)' then
      handled[i] = 'HPCToolkit: documentation conversion script'
      check(not info.kind)
      info.kind, info.cmd = 'latex2man', ex
      info.ruleset = ruleset
    elseif c:find '$%(LIBTOOL%)' or ex:find '/libtool%s' then
      handled[i] = 'CC: LibTool-style compile command'
      check(not info.kind)
      info.kind, info.cmd = 'libtool', ex:match ';%s*(.+)' or ex
      info.ruleset = ruleset
    elseif c == ([[@list1=''; list2='$(man_MANS)'; test -n "$(man1dir)" && test
    -n "`echo $$list1$$list2`" || exit 0; echo " $(MKDIR_P)
    '$(DESTDIR)$(man1dir)'"; $(MKDIR_P) "$(DESTDIR)$(man1dir)" || exit 1; { for
    i in $$list1; do echo "$$i"; done; if test -n "$$list2"; then for i in
    $$list2; do echo "$$i"; done | sed -n '/\.1[a-z]*$$/p'; fi; } | while read
    p; do if test -f $$p; then d=; else d="$(srcdir)/"; fi; echo "$$d$$p"; echo
    "$$p"; done | sed -e 'n;s,.*/,,;p;h;s,.*\.,,;s,^[^1][0-9a-z]*$$,1,;x' -e
    's,\.[0-9a-z]*$$,,;$(transform);G;s,\n,.,' | sed 'N;N;s,\n, ,g' | { list=;
    while read file base inst; do if test "$$base" = "$$inst"; then list="$$list
    $$file"; else echo " $(INSTALL_DATA) '$$file'
    '$(DESTDIR)$(man1dir)/$$inst'"; $(INSTALL_DATA) "$$file"
    "$(DESTDIR)$(man1dir)/$$inst" || exit $$?; fi; done; for i in $$list; do
    echo "$$i"; done | $(am__base_list) | while read files; do test -z
    "$$files" || { echo " $(INSTALL_DATA) $$files '$(DESTDIR)$(man1dir)'";
    $(INSTALL_DATA) $$files "$(DESTDIR)$(man1dir)" || exit $$?; }; done;
    }]]):gsub('\n%s*', ' ') then
      handled[i] = 'HPCToolkit: manfile install script'
      check(not info.kind)
      info.kind,info.dstdir = 'install', dir(path(r.expand '$(man1dir)').path)
    elseif c == ([[for m in $(modules); do $(INSTALL_PROGRAM) libebl_$${m}.so
    $(DESTDIR)$(libdir)/$(LIBEBL_SUBDIR)/libebl_$${m}-$(PACKAGE_VERSION).so; ln
    -fs libebl_$${m}-$(PACKAGE_VERSION).so
    $(DESTDIR)$(libdir)/$(LIBEBL_SUBDIR)/libebl_$${m}.so;
    done]]):gsub('\n%s*', ' ') then
      handled[i] = 'Elfutils: libebl module install script'
      check(not info.kind)
      info.kind, info.subs = 'loopinstall', {}
      local d = dir(path(r.expand '$(DESTDIR)$(libdir)/$(LIBEBL_SUBDIR)').path)
      local v = r.expand '$(PACKAGE_VERSION)'
      for m in r.expand '$(modules)':gmatch '%g+' do
        local s = {}
        s.deps = {make(path(r.cwd..'libebl_'..m..'.so'), ruleset)}
        s.src = s.deps[1].ltso or s.deps[1].path
        s.dst = d..'libebl_'..m..'-'..v..'.so'
        s.links = {{d..'libebl_'..m..'.so', 'libebl_'..m..'-'..v..'.so'}}
        table.insert(info.subs, s)
      end
    elseif c == ([[@list1='$(dist_man1_MANS)'; list2=''; test -n "$(man1dir)" &&
    test -n "`echo $$list1$$list2`" || exit 0; echo " $(MKDIR_P)
    '$(DESTDIR)$(man1dir)'"; $(MKDIR_P) "$(DESTDIR)$(man1dir)" || exit 1; { for
    i in $$list1; do echo "$$i"; done; if test -n "$$list2"; then for i in
    $$list2; do echo "$$i"; done | sed -n '/\.1[a-z]*$$/p'; fi; } | while read
    p; do if test -f $$p; then d=; else d="$(srcdir)/"; fi; echo "$$d$$p"; echo
    "$$p"; done | sed -e 'n;s,.*/,,;p;h;s,.*\.,,;s,^[^1][0-9a-z]*$$,1,;x' -e
    's,\.[0-9a-z]*$$,,;$(transform);G;s,\n,.,' | sed 'N;N;s,\n, ,g' | { list=;
    while read file base inst; do if test "$$base" = "$$inst"; then list="$$list
    $$file"; else echo " $(INSTALL_DATA) '$$file'
    '$(DESTDIR)$(man1dir)/$$inst'"; $(INSTALL_DATA) "$$file"
    "$(DESTDIR)$(man1dir)/$$inst" || exit $$?; fi; done; for i in $$list; do
    echo "$$i"; done | $(am__base_list) | while read files; do test -z "$$files"
    || { echo " $(INSTALL_DATA) $$files '$(DESTDIR)$(man1dir)'"; $(INSTALL_DATA)
    $$files "$(DESTDIR)$(man1dir)" || exit $$?; }; done; }]])
    :gsub('\n%s*', ' ') then
      handled[i] = 'Elfutils: manfile install script'
      check(not info.kind)
      info.kind, info.dstdir = 'install', dir(path(r.expand '$(DESTDIR)$(man1dir)').path)
    elseif c == ([[@list1='$(notrans_dist_man3_MANS)'; list2=''; test -n
    "$(man3dir)" && test -n "`echo $$list1$$list2`" || exit 0; echo " $(MKDIR_P)
    '$(DESTDIR)$(man3dir)'"; $(MKDIR_P) "$(DESTDIR)$(man3dir)" || exit 1; { for
    i in $$list1; do echo "$$i"; done; if test -n "$$list2"; then for i in
    $$list2; do echo "$$i"; done | sed -n '/\.3[a-z]*$$/p'; fi; } | while read
    p; do if test -f $$p; then d=; else d="$(srcdir)/"; fi; echo "$$d$$p"; echo
    "$$p"; done | sed 'n;s,.*/,,;p;s,\.[^3][0-9a-z]*$$,.3,' | sed 'N;N;s,\n, ,g'
    | { list=; while read file base inst; do if test "$$base" = "$$inst"; then
    list="$$list $$file"; else echo " $(INSTALL_DATA) '$$file'
    '$(DESTDIR)$(man3dir)/$$inst'"; $(INSTALL_DATA) "$$file"
    "$(DESTDIR)$(man3dir)/$$inst" || exit $$?; fi; done; for i in $$list; do
    echo "$$i"; done | $(am__base_list) | while read files; do test -z "$$files"
    || { echo " $(INSTALL_DATA) $$files '$(DESTDIR)$(man3dir)'"; $(INSTALL_DATA)
    $$files "$(DESTDIR)$(man3dir)" || exit $$?; }; done; }]])
    :gsub('\n%s*', ' ') then
      handled[i] = 'Elfutils: manfile install script'
      check(not info.kind)
      info.kind, info.dstdir = 'install', dir(path(r.expand '$(DESTDIR)$(man3dir)').path)
    elseif c == ([[@list1='$(notrans_dist_man1_MANS)'; list2=''; test -n
    "$(man1dir)" && test -n "`echo $$list1$$list2`" || exit 0; echo " $(MKDIR_P)
    '$(DESTDIR)$(man1dir)'"; $(MKDIR_P) "$(DESTDIR)$(man1dir)" || exit 1; { for
    i in $$list1; do echo "$$i"; done; if test -n "$$list2"; then for i in
    $$list2; do echo "$$i"; done | sed -n '/\.1[a-z]*$$/p'; fi; } | while read
    p; do if test -f $$p; then d=; else d="$(srcdir)/"; fi; echo "$$d$$p"; echo
    "$$p"; done | sed 'n;s,.*/,,;p;s,\.[^1][0-9a-z]*$$,.1,' | sed 'N;N;s,\n, ,g'
    | { list=; while read file base inst; do if test "$$base" = "$$inst"; then
    list="$$list $$file"; else echo " $(INSTALL_DATA) '$$file'
    '$(DESTDIR)$(man1dir)/$$inst'"; $(INSTALL_DATA) "$$file"
    "$(DESTDIR)$(man1dir)/$$inst" || exit $$?; fi; done; for i in $$list; do
    echo "$$i"; done | $(am__base_list) | while read files; do test -z "$$files"
    || { echo " $(INSTALL_DATA) $$files '$(DESTDIR)$(man1dir)'"; $(INSTALL_DATA)
    $$files "$(DESTDIR)$(man1dir)" || exit $$?; }; done; }]])
    :gsub('\n%s*', ' ') then
      handled[i] = 'Elfutils: manfile install script'
      check(not info.kind)
      info.kind, info.dstdir = 'install', dir(path(r.expand '$(DESTDIR)$(man1dir)').path)
    elseif c == ([[@list1='$(notrans_dist_man8_MANS)'; list2=''; test -n
    "$(man8dir)" && test -n "`echo $$list1$$list2`" || exit 0; echo " $(MKDIR_P)
    '$(DESTDIR)$(man8dir)'"; $(MKDIR_P) "$(DESTDIR)$(man8dir)" || exit 1; { for
    i in $$list1; do echo "$$i"; done; if test -n "$$list2"; then for i in
    $$list2; do echo "$$i"; done | sed -n '/\.8[a-z]*$$/p'; fi; } | while read
    p; do if test -f $$p; then d=; else d="$(srcdir)/"; fi; echo "$$d$$p"; echo
    "$$p"; done | sed 'n;s,.*/,,;p;s,\.[^8][0-9a-z]*$$,.8,' | sed 'N;N;s,\n, ,g'
    | { list=; while read file base inst; do if test "$$base" = "$$inst"; then
    list="$$list $$file"; else echo " $(INSTALL_DATA) '$$file'
    '$(DESTDIR)$(man8dir)/$$inst'"; $(INSTALL_DATA) "$$file"
    "$(DESTDIR)$(man8dir)/$$inst" || exit $$?; fi; done; for i in $$list; do
    echo "$$i"; done | $(am__base_list) | while read files; do test -z "$$files"
    || { echo " $(INSTALL_DATA) $$files '$(DESTDIR)$(man8dir)'"; $(INSTALL_DATA)
    $$files "$(DESTDIR)$(man8dir)" || exit $$?; }; done; }]])
    :gsub('\n%s*', ' ') then
      handled[i] = 'Elfutils: manfile install script'
      check(not info.kind)
      info.kind, info.dstdir = 'install', dir(path(r.expand '$(DESTDIR)$(man8dir)').path)
    elseif c == ([[-for file in $(PLUGIN_CONFIG_FILES) ; do cp -f
    "$(plugin_srcdir)/$$file" "$(DESTDIR)$(plugin_instdir)/$$file" ;
    done]]):gsub('\n%s*', ' ') then
      handled[i] = 'HPCToolkit: plugins install script'
      check(not info.kind)
      assert(#info.deps == 0)
      info.kind = 'install'
      info.dstdir = dir(path(r.expand '$(DESTDIR)$(plugin_instdir)').path)
      local d = dir(r.expand '$(plugin_srcdir)')
      for file in r.expand '$(PLUGIN_CONFIG_FILES)':gmatch '%g+' do
        table.insert(info.deps, make(path(d..file, r.cwd), ruleset))
      end
    elseif c:find '$%(COMPILE%.?o?s?%)' or c:find '$%(C[CX]X?%)' then
      handled[i] = 'CC: Autotools-style compile command'
      check(not info.kind)
      info.kind, info.cmd = 'compile', ex:match ';%s*(.+)' or ex
      info.ruleset = ruleset
    elseif c:find '$%(CX?X?_FLAGS%)' then
      handled[i] = 'CC: CMake-style compile command'
      check(not info.kind)
      info.kind, info.cd, info.cmd = 'compile', ex:match '(.-)&&%s*(.+)'
      if not info.cd then info.cmd = ex
      else info.cwd = dir(path(info.cd:match '%s+(%g+)').path) end
      info.ruleset = ruleset
    elseif c:find '$%(%g*_?AR%)' then
      handled[i] = 'AR: Autotools-style archiving command'
      check(not info.kind)
      info.kind, info.cmd = 'ar', ex:match ';%s*(.+)' or ex
    elseif c:find '$%(RANLIB%)' then
      handled[i] = 'AR: Ranlib'
      check(info.kind == 'ar')
      info.ranlib = true
      info.ruleset = ruleset
    elseif c:find '$%(LINK%)' then
      handled[i] = 'LD: Autotools-style linking commmand'
      check(not info.kind or info.kind == 'ld')
      info.kind, info.cmd = 'ld', ex:match ';%s*(.+)' or ex
    elseif c:find '%-P cmake_install%.cmake%f[%s\0]' then
      handled[i] = 'CMake: install script'
      check(not info.kind)
      info.ruleset = ruleset
      info.kind = 'cmakeinstall'
    elseif ex:find '^ln' then
      if info.kind == 'ld' then
        handled[i] = '*: Link command'
        info.linkto = ex:match '%g+$'
      elseif info.kind == 'install' then
        handled[i] = '*: Link command'
        info.links = info.links or {}
        local f,t = ex:match '(%g+)%s+(%g+)$'
        table.insert(info.links, {path(t, '').path, f})
      end
    elseif c:find '^gawk' then handled[i] = 'Awk: Elfutils gawk command'
      check(not info.kind)
      info.kind, info.cmd = 'awk', ex
    elseif c:find '^sed' or ex:find '^[^;]+;%s*sed' then
      handled[i] = 'Sed: Elfutils sed command'
      check(not info.kind)
      info.kind, info.cmd, info.postsort = 'sed', ex:match ';(.-)%s|%s(.+)'
      if not info.cmd then info.cmd = ex:match ';(.+)' or ex end
    elseif ex:find ';%s*m4' then handled[i] = 'M4: Elfutils m4 command'
      check(not info.kind)
      info.kind, info.cmd = 'm4', ex:match ';%s*(.+)' or ex
    elseif c:find './%g+_gendis' then handled[i] = 'Elfutils: Gendis command'
      check(not info.kind)
      info.kind, info.cmd = 'gendis', ex:match ';%s*(.+)' or ex
    elseif c:find '$%(YLWRAP%)' then
      handled[i] = 'Elfutils: ylwrap command'
      check(not info.kind)
      if not glob 'config/ylwrap' then
        local b64 = subp.slexec{{'gzip', '-n', rein=realsrcdir..'config/ylwrap'},
          {'base64', '-w0'}}
        tup.rule('^o Copy %o^ '..subp.shell(
          {{'echo', b64}, {'base64', '-d'}, {'gzip', '-d', reout='%o'}},
          {'chmod', '+x', '%o'}
        ), {'config/ylwrap'})
      end
      info.kind = 'ylwrap'
      local ylwrap = unmagic(r.expand '$(YLWRAP)')
      info.cmd = './config/ylwrap '..ex:match(ylwrap..'%s+(.+)')
    elseif c:find '/stringify%.py' then
      handled[i] = 'HPCToolkit: Stringification'
      check(not info.kind)
      info.kind, info.cmd = 'stringify', ex
    elseif ex:find "^echo 'ELFUTILS_" then
      handled[i] = 'LD: Elfutils mapfile echo'
      check(not info.kind)
      info.kind = 'ld'
      tup.rule('^o Wrote %o^ '..ex, {ex:match '> (%g+)'})
      table.insert(info.deps, path(ex:match '> (%g+)', ''))
    elseif c == '@$(textrel_check)' then
      handled[i] = 'LD: Elfutils TEXTREL assertion'
      check(info.kind == 'ld')
      info.assert = ' && (if readelf -d %o | grep -Fq TEXTREL; then '
        ..'echo "WARNING: TEXTREL found in \'%o\'"; exit 1; fi)'
    elseif ex:find '^chmod %+x' then
      handled[i] = '*: Post-chmod command'
      check(info.kind == 'sed')
      info.postexec = true
    elseif ex:find '^mv' then
      handled[i] = '*: Post-move command'
      check(info.kind == 'awk' or info.kind == 'sed' or info.kind == 'm4'
        or info.kind == 'gendis')
      getopt(ex, 'f,', {
        [false] = function(x)
          if not info.mvfrom then info.mvfrom = x
          elseif not info.mvto then info.mvto = x
          else error(x) end
        end,
      })
    elseif c:find '^@echo' then handled[i] = "Make: status message"
    elseif c:find '> "$%(hash_file%)"$' then handled[i] = 'HPCToolkit: hash thing'
    else printout = true end
  end
  if info.error ~= nil then printout = true end

  -- Try to invoke the translator, if we fail print out the rule.
  if translations[info.kind] then
    if translations[info.kind](info) then printout = true end
  elseif info.kind then printout = true end

  -- If anything had troubles, print out a note to the output on the subject.
  if printout and #r > 0 then
    local function p(x, y) return x..(y and x ~= y and ' ('..y..')' or '') end
    print(p(info.path, fn.path)..' | '..(#r.cwd > 0 and r.cwd or '.')..':')
    for i,d in ipairs(info.deps) do print('  + '..p(d.path, r.deps[i] and r.deps[i].path)) end
    for i,c in ipairs(r) do
      if handled[i] then print('  # '..handled[i]) end
      print('  '..(handled[i] and '^' or '$')..' '..c)
      if not handled[i] then print('  % '..r.ex[i]) end
    end
    if info.kind then
      print('  > '..info.kind..(translations[info.kind] and '()' or '')..' '
        ..serpent.block(info, {comment=false, maxlevel=2}))
    end
    print()
  end
  if info.error ~= nil then error(info.error) end
  r.made,madefiles[fn.path] = info,info
  return info
end

-- Step 5: Based on the info extracted from above, break up and translate into
-- something that Tup can handle with ease.
function translations.make(info)  -- Recursive make call(s)
  for i,t in ipairs(info.targets) do
    local rs = info.rulesets and info.rulesets[i] or info.ruleset
    make(t, rs)
  end
end
function translations.ar(info)  -- Archive (static library) command
  local r = {inputs={}, outputs={info.path}}
  r.command = '^o AR %o^ ar '..(info.ranlib and 's' or 'S')
    ..(info.thin and 'T' or '')..'cr %o %f'
  local function pmatch(p)
    for _,a in ipairs(info.deps) do
      if a.original == p then return a.path
      elseif a.path == p then return p end
    end
    return make(path(p, info.cwd), info.ruleset).path
  end
  local cnt = 0
  for w in info.cmd:gmatch '%g+' do
    cnt = cnt + 1
    if cnt > 3 then
      if w:find '/XXX$' then  -- Hack for Elfutils
        local t = tup.glob(path(w, info.cwd).path:gsub('XXX$', '*.o'))
        table.move(t, 1,#t, #r.inputs+1, r.inputs)
      else table.insert(r.inputs, pmatch(w)) end
    end
  end
  tup.frule(r)
end
function translations.compile(info)  -- Compilation command
  local function pmatch(p)
    for _,a in ipairs(info.deps) do
      if a.original == p then return a.path
      elseif a.path == p then return p end
    end
    return make(path(p, info.cwd), info.ruleset).path
  end
  local here = dir(info.cwd:gsub('[^/]+', '..'))
  local herep = #info.cwd > 0 and here or '.'
  local cd = #info.cwd > 0 and 'cd '..info.cwd..' && ' or ''
  local function hpath(p)
    p = canonicalize(here..p, info.cwd)
    return #p == 0 and '.' or p
  end
  local r = {inputs={extra_inputs={'<_gen>'}}, outputs={}}
  r.command = '^o CC %o^ '..cd..subp.shell(getopt(info.cmd,
    'D:I:std:W;w,f:g,O;c,o:l:pthread,m:no-pie,pie,', {
    [true] = function(cc)
      if cc:find '%+%+' then return cc,table.unpack(cxxflags)
      else return cc,table.unpack(cppflags) end
    end,
    [false] = function(p)
      p = p:gsub('^`test %-f.-`/?', '')
      table.insert(r.inputs, pmatch(p))
      return hpath(r.inputs[#r.inputs])
    end,
    o = function(p)
      table.insert(r.outputs, info.path == p and p or path(p, info.cwd).path)
      return '?',hpath(r.outputs[#r.outputs])
    end,
    I = function(p)
      p = path(p, info.cwd)
      return '?',p.path and (#p.path == 0 and herep or hpath(p.path)) or p.absolute
    end,
    D = function(x) return '?',(x:gsub(unmagic(tmpdir), '')) end,
  }))
  table.move(exdeps, 1,#exdeps, #r.inputs.extra_inputs+1, r.inputs.extra_inputs)
  for i=#r.inputs+1,#info.deps do if info.deps[i].kind then
    table.insert(r.inputs.extra_inputs, info.deps[i].path)
  end end
  info.inputs = r.inputs
  info.outputs = r.outputs
  tup.frule(r)
end
local extrald = {}
function translations.ld(info)  -- Linking command
  local function pmatch(p)
    for _,a in ipairs(info.deps) do
      if a.original == p then return a.path
      elseif a.path == p then return p end
    end
    p = make(path(p, info.cwd), info.ruleset)
    return p.path, p.external
  end
  local r = {inputs={extra_inputs={}}, outputs={extra_outputs={}}}
  local searchpaths,libs = {},{}

  local elibs = {}
  local function link(f)
    local e = extrald[f]
    if e then table.move(e, 1,#e, #elibs, elibs) end
    return not not e
  end

  r.command = getopt(info.cmd,
    'o:std:W;g,O;shared,l:D:f:L:I:pthread,m:no-pie,pie,static,', {
    [true] = function(cc) return cc,table.unpack(ldflags) end,
    [false] = function(p)
      local e
      p,e = pmatch(p)
      if not e then table.insert(r.inputs, p); link(p) end
      return p
    end,
    o = function(p)
      if #r.outputs == 0 then
        r.outputs[1] = info.path == p and p or path(p, info.cwd).path
        return '?','%o'
      else return false end
    end,
    W = function(x)
      if x:find '^l,' then
        return '?',(x:gsub(',%-%-?rpath[^,]*,([^,]*)', function(ps)
          return ',-rpath-link,'..ps:gsub('[^;:]+', function(p)
            p = path(p, info.cwd)
            if p.build then table.insert(searchpaths, p) end
            p = dir(p.path or p.absolute)
            if p:find '^install/' then return '' end
            return p
          end)
        end):gsub(',%-%-?soname,([^,]+)', function(so)
          return ',--soname,'..so:match '[^/,]+$'
        end))
      end
    end,
    L = function(p)
      p = path(p, info.cwd)
      if p.build then table.insert(searchpaths, p) end
      return '?',p.path and #p.path == 0 and '.' or p.path or p.absolute
    end,
    D = function(x) return '?',(x:gsub(unmagic(tmpdir), '')) end,
    I = false,  -- Includes do nothing when just linking
    static = function() info.ldstatic = true end,
    l = function(x) table.insert(libs, 'lib'..x..'.so') end,
  })
  for _,l in ipairs(libs) do for _,p in ipairs(searchpaths) do
    if link(dir(p.path)..l) then break end
  end end
  for i=#r.inputs+1,#info.deps do if not info.deps[i].external then
    table.insert(r.inputs.extra_inputs, info.deps[i].path)
    if info.deps[i].kind == 'ld' then link(info.deps[i].path)
    elseif info.deps[i].ltmode == 'link' then link(info.deps[i].ltso) end
  end end
  table.move(elibs, 1,#elibs, #r.inputs.extra_inputs+1, r.inputs.extra_inputs)
  table.move(exdeps, 1,#exdeps, #r.inputs.extra_inputs+1, r.inputs.extra_inputs)

  r.command = '^o LD %o^ '..subp.shell(r.command)..(info.assert or '')
  extrald[r.outputs[1]] = elibs
  table.insert(elibs, r.outputs[1])
  if info.linkto then
    r.command = r.command..' && ln -s '..r.outputs[1]:match '[^/]+$'..' '..info.linkto
    r.outputs.extra_outputs[1] = info.linkto
    extrald[info.linkto] = elibs
    table.insert(elibs, info.linkto)
  end

  tup.frule(r)
end
local instdedup = {}
function translations.install(info)
  if not info.src then
    for _,f in ipairs(info.deps) do
      local ei,pelf = nil, ''
      if f.kind == 'ld' or f.ltmode == 'link' then
        ei = {topcwd..'../external/patchelf/<build>'}
        pelf = " '"..runpath.."'"
      end
      local d = info.dstdir..(f.ltso or f.path):match '[^/]+$'
      if not instdedup[d] then  -- Hack for HPCToolkit
        instdedup[d] = true
        tup.rule({f.ltso or f.path, extra_inputs=ei},
          '^o Install %o^ '..topcwd..'install.sh %f %o'..pelf,
          {d, '<build>'})
        if f.ltar then
          tup.rule(f.ltar, '^o Install %o^ '..topcwd..'install.sh %f %o',
            {info.dstdir..f.ltar:match '[^/]+$', '<build>'})
        end
      end
    end
  else
    if instdedup[info.dst] then return end  -- Hack for HPCToolkit
    instdedup[info.dst] = true
    local ei,pelf = nil, ''
    for _,f in ipairs(info.deps) do
      if f.kind == 'ld' or f.ltmode == 'link' then
        ei = {topcwd..'../external/patchelf/<build>'}
        pelf = " '"..runpath.."'"
        break
      end
    end
    tup.rule({info.src, extra_inputs=ei}, '^o Install %o^ '..topcwd..'install.sh %f %o'..pelf,
      {info.dst, '<build>'})
    if info.links then for _,l in ipairs(info.links) do
      local t,f = l[1],l[2]
      tup.rule({t:match '(.-)[^/]+$'..f}, '^o Symlink %o^ ln -s '..f..' %o',
        {t, '<build>'})
    end end
  end
end

function translations.loopinstall(info)
  -- Effectively a loop of translations.install, for Elfutils
  for _,i in ipairs(info.subs) do
    translations.install(i)
  end
end

function translations.cmakeld(info)
  local cmd
  for l in io.lines(tmpdir..info.cwd..info.script) do
    if not cmd then cmd = l
    else info.ranlib = true end
  end
  info.cmd = cmd
  if info.ranlib then translations.ar(info)
  else translations.ld(info) end
  if info.links then for _,l in ipairs(info.links) do
    local t,f = l[1],l[2]
    tup.rule({t:match '(.-)[^/]+$'..f}, '^o Symlink %o^ ln -s '..f..' %o', {t})
  end end
end
function translations.cmakeinstall()
  local parsecache,dedup,odedup = {},{},{}
  local function parse(fn)
    if parsecache[fn] then return end
    parsecache[fn] = true
    local data
    do
      local f = assert(io.open(fn))
      data = f:read 'a'
      f:close()
    end
    for inc in data:gmatch '%f[\0\n]%s*include(%b())' do
      inc = inc:sub(2,-2):gsub('^"', ''):gsub('"$', '')
      parse(inc)
    end
    for inst in data:gmatch '%f[\0\n]%s*file(%b())' do
      inst = inst:sub(2,-2)
      if inst:match '%g+' == 'INSTALL' then
        local skip = {INSTALL=true, OPTIONAL=true, FILES=true}
        local outdir, ins, ty, renm = nil, {}, nil, nil
        for a in inst:gmatch '%g+' do
          if outdir == false then
            a = a:gsub('"', ''):gsub('${CMAKE_INSTALL_PREFIX}', 'install/')
            outdir = dir(path(a).path)
          elseif ty == false then ty = a
          elseif renm == false then renm = a:gsub('"', '')
          elseif a == 'DESTINATION' then outdir = false
          elseif a == 'TYPE' then ty = false
          elseif a == 'RENAME' then renm = false
          elseif not skip[a] then
            assert(a:find '"', a)
            a = a:gsub('"', ''):gsub('${CMAKE_INSTALL_PREFIX}', 'install/')
            a = path(a).path
            -- Hacks for Dyninst, mostly.
            if a:find '%.cmake$' or a:find '%.txt$' then
              if not odedup[a] then
                odedup[a] = true
                local d = tmpdir
                if not subp.stestexec{'stat', d..a, onlyout=true, reout=false} then
                  d = fullsrcdir
                end
                local b64 = subp.slexec{{'gzip', '-n', rein=d..a}, {'base64', '-w0'}}
                tup.rule('^o Copy %o^ '..subp.shell{
                  {'echo', b64}, {'base64', '-d'}, {'gzip', '-d', reout='%o'}
                }, {a, '<_gen>'})
              end
            end
            if not a:find '%.pdf$' then table.insert(ins, a) end
          end
        end
        if #ins > 0 and ty ~= 'DIRECTORY' then
          local ei, pelf = {},''
          if ty == 'SHARED_LIBRARY' or ty == 'EXECUTABLE' then
            ei[1] = topcwd..'../external/patchelf/<build>'
            pelf = " '"..runpath.."'"
          end
          if renm then
            assert(#ins == 1)
            if not dedup[ins[1]] then
              tup.rule({ins[1], extra_inputs=ei},
                '^o Install %o^ '..topcwd..'install.sh %f %o'..pelf,
                {outdir..renm, '<build>'})
              dedup[ins[1]] = true
            end
          else
            for _,v in ipairs(ins) do if not dedup[v] then
              tup.rule({v, extra_inputs=ei},
                '^o Install %o^ '..topcwd..'install.sh %f %o'..pelf,
                {outdir..v:match '[^/]+$', '<build>'})
              dedup[v] = true
            end end
          end
        end
      end
    end
  end
  parse(tmpdir..'cmake_install.cmake')
end

local ltldflags = {}
function translations.libtool(info)
  local mode,bcmd = info.cmd:match '%-%-mode=(%g+)%s+(.+)'
  bcmd = bcmd:gsub('%f[%S]%-rpath%s+(%g+)', '-Wl,-rpath,%1')
  local origp = info.path
  if mode == 'compile' then
    assert(not ltldflags[info.path])
    ltldflags[info.path] = {}
    for w in bcmd:gmatch '%f[%S]%-[lL]%g+%f[%s\0]' do
      table.insert(ltldflags[info.path], w) end
    info.cmd = bcmd:gsub('%-o%s+(%g+)%.lo', '-o %1.o')
    info.path = origp:gsub('%.lo$', '.o')
    translations.compile(info)
    info.cmd = bcmd:gsub('%-o%s+(%g+)%.lo', '-o %1.os')..' -fPIC -DPIC'
    info.path = origp:gsub('%.lo$', '.os')
    translations.compile(info)
    info.ltmode = 'compile'
  elseif mode == 'link' then
    assert(not ltldflags[info.path])
    ltldflags[info.path] = {}
    for _,l in bcmd:gmatch '%g+%.l[oa]' do
      l = ltldflags[l] or {}
      table.move(l, 1,#l, #ltldflags[info.path], ltldflags[info.path])
    end
    for w in bcmd:gmatch '%f[%S]%-[lL]%g+%f[%s\0]' do
      table.insert(ltldflags[info.path], w) end
    local lf = table.concat(ltldflags[info.path], ' ')
    if info.path:find '%.la$' then
      info.cmd = bcmd:gsub('%-o%s+(%g+)%.la', '-o %1.so')..' -shared '..lf
      info.path = origp:gsub('%.la$', '.so')
      info.ltso = info.path
      translations.ld(info)
      info.cmd = {}
      getopt(bcmd, 'o:std:W;g,O;shared,l:D:f:L:I:', {
        [false]=function(x)
          if not x:find '%.a$' then table.insert(info.cmd, x) end
        end,
      })
      info.cmd = 'ar cr output.a '..table.concat(info.cmd, ' ')
      info.ranlib,info.thin = true,true
      info.path = origp:gsub('%.la$', '.a')
      info.ltar = info.path
      translations.ar(info)
      info.ltmode = 'link'
    else
      info.cmd = bcmd..' '..lf
      info.ltso = info.path
      translations.ld(info)
      info.ltmode = 'link'
    end
  else return true end
end
function translations.latex2man(info)
  local r = {inputs={}, outputs={}}
  r.command = '^o DOC %o^ '..subp.shell(getopt(info.cmd, 'H,t:', {
    [true] = function(x) return path(x, '').path end,
    t = function(x) return '?',path(x, '').path end,
    [false] = function(p)
      p = path(p, '')
      if #r.inputs == 0 then p = make(p, info.ruleset); r.inputs[1] = p.path
      else r.outputs[1] = p.path end
      return p.path
    end,
  }))
  tup.frule(r)
end
function translations.stringify(info)
  local r = {inputs={}, outputs={[2]='<_gen>'}}
  r.command = '^o STR %o^ '..subp.shell(getopt(info.cmd, '', {
    ['<'] = function(p)
      p = path(p); assert(p.source)
      r.inputs[1] = p.path
      return '?', '%f'
    end,
    ['>'] = function(p)
      p = path(p)
      if p.path == info.mvfrom then p = path(info.mvto) end
      if p.source then  -- We move this file into the build tree
        r.outputs[1] = p.stem
      else
        assert(p.build, p.absolute)
        r.outputs[1] = p.path
      end
      return '?', '%o'
    end,
  }))
  tup.frule(r)
end

function translations.ylwrap(info)
  info.cmd = info.cmd:gsub('`echo%s+(%g+)%s+|.*`', function(f)
    return f:gsub('cc$','hh'):gsub('cpp$','hpp'):gsub('cxx$','hxx')
      :gsub('c%+%+$','h++'):gsub('c$','h')
  end)
  local r = {inputs={extra_inputs={'config/ylwrap'}}, outputs={}}
  local froms = {}
  for w in info.cmd:gmatch '%g+' do
    if not r.command then r.command = {w}
    elseif #r.inputs == 0 then
      r.inputs[1] = info.deps[1].path; table.insert(r.command, '%f')
    elseif w == '--' then break
    elseif #froms == #r.outputs then  -- Next pair
      table.insert(froms, w)
      table.insert(r.command, w)
    else  -- Finishing up a pair
      w = w:find('^'..unmagic(info.cwd)) and w or path(w, info.cwd).path
      if not w:find '%.output$' then
        table.insert(r.outputs, w)
      end
      table.insert(r.command, w)
    end
  end
  r.command = '^o GEN %o^ LD_PRELOAD= '..table.concat(r.command, ' ')
    ..' '..info.cmd:match '%-%-.*'
    ..' && stat %f %o >/dev/null && touch %o'
  table.insert(r.outputs, '<_gen>')
  tup.frule(r)
end
function translations.awk(info)  -- Awk call
  local r = {inputs={}, outputs={[2]='<_gen>'}}
  r.command = '^o AWK %o^ '..subp.shell(getopt(info.cmd, 'f:', {
    f = function(p)
      p = path(p); assert(p.source)
      return '?',p.path
    end,
    [false] = function(p)
      p = path(p); assert(p.source)
      r.inputs[1] = p.path
      return '?', '%f'
    end,
    ['>'] = function(p)
      p = path(p); assert(p.source)
      if p.path == info.mvfrom then p = path(info.mvto); assert(p.source) end
      r.outputs[1] = p.stem
      return '?', '%o'
    end,
  }))
  tup.frule(r)
end
function translations.sed(info)  -- Sed call
  local r = {inputs={}, outputs={[2]='<_gen>'}}
  local eseen = false
  r.command = '^o SED %o^ '..subp.shell({getopt(info.cmd, 'e:', {
    e = function(x) eseen = true; return '?',(x:gsub('%%', '%%%%')) end,
    [false] = function(x)
      if not eseen then eseen = true; return '?',(x:gsub('%%', '%%%%')) end
      assert(#r.inputs == 0)
      r.inputs[1] = info.deps[1].path
      return '?', '%f'
    end,
    ['>'] = function(p)
      assert(r.outputs[1] == nil)
      p = path(p)
      if p.path == info.mvfrom then p = path(info.mvto) end
      r.outputs[1] = p.stem
      return '?', '%o'
    end,
  }), info.postsort and getopt(info.postsort, 'u,', {
    [false] = error,
    ['>'] = function(p)
      assert(r.outputs[1] == nil)
      p = path(p)
      if p.path == info.mvfrom then p = path(info.mvto) end
      r.outputs[1] = p.stem
      return '?', '%o'
    end,
  })}, info.postexec and {'chmod', '+x', '%o'})
  tup.frule(r)
end
function translations.m4(info)
  local r = {inputs={}, outputs={[2]='<_gen>'}}
  r.command = '^o M4 %o^ '..subp.shell(getopt(info.cmd, 'D:', {
    [false] = function(p)
      assert(#r.inputs == 0)
      p = path(p); assert(p.source, p.path)
      r.inputs[1] = p.path
      return '?','%f'
    end,
    ['>'] = function(p)
      p = path(p)
      if p.path == info.mvfrom then p = path(info.mvto) end
      assert(p.build)
      r.outputs[1] = p.path
      return '?', '%o'
    end,
  }))
  tup.frule(r)
end
function translations.gendis(info)
  info.inputs,info.outputs = {extra_inputs={}},{}
  info.command = '^o GEN %o^ '..subp.shell(getopt(info.cmd, '', {
    [true] = function()
      info.inputs.extra_inputs[1] = info.deps[2].path
      return info.inputs.extra_inputs[1]
    end,
    [false] = function()
      assert(#info.inputs == 0)
      info.inputs[1] = info.deps[1].path
      return '?','%f'
    end,
    ['>'] = function(p)
      p = path(p)
      if p.path == info.mvfrom then p = path(info.mvto) end
      info.outputs[1] = p.build and p.path or p.stem
      return '?', '%o'
    end,
  }))
  tup.frule(info)
end

-- Step 6: Some files still aren't handled, outputs from Autotools and CMake.
-- Use gzip+base64 for storage in Tup's db, and copy over to the output.
for _,f in ipairs{
  -- Elfutils
  'config.h', 'config/libelf.pc', 'config/libdw.pc', 'config/libdebuginfod.pc',
  'version.h',
  -- Dyninst
  'common/h/dyninstversion.h',
  -- HPCToolkit
  'src/include/hpctoolkit-config.h', 'src/tool/hpcstruct/hpcstruct',
  'src/tool/hpcstruct/dotgraph', 'src/tool/hpcprof/hpcprof',
  'src/tool/hpcprof-mpi/hpcprof-mpi', 'src/tool/hpcproftt/hpcproftt',
  '@config/config.guess', 'src/tool/hpcrun/scripts/hpcrun',
  'src/tool/hpcrun/scripts/hpcsummary', 'src/tool/hpcfnbounds/hpcfnbounds',
} do
  local d = tmpdir
  if f:sub(1,1) == '@' then d,f = fullsrcdir,f:match '^@(.*)' end
  if subp.stestexec{'stat', d..f, onlyout=true, reout=false} then
    local b64 = subp.slexec{{'gzip', '-n', rein=d..f}, {'base64', '-w0'}}
    tup.rule('^o Copy %o^ '..subp.shell{
      {'echo', b64}, {'base64', '-d'}, {'gzip', '-d', reout='%o'}
    }, {f, '<_gen>'})
  end
end

-- Step 7: Fire it off!
make(path 'all', parsemakefile 'Makefile')
make(path 'install', parsemakefile 'Makefile')

-- Error with a magic value to ensure the thing gets finalized
error(finalize)
end, function(err)
  finalize()
  if err ~= finalize then
    finalerror = debug.traceback(tostring(err), 2)
  end
end)
if finalerror then error(finalerror) end

end
