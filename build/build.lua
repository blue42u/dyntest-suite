-- luacheck: std lua53, new globals tup

-- Handy functions for handling subprocesses
local function pclose(f)
  local ok,kind,code = f:close()
  if not kind then return
  elseif not ok then
    if kind == 'exit' then error('Subprocess exited with code '..code)
    elseif kind == 'signal' then error('Subprocess was killed by signal '..code)
    else error('Subprocess exited in a weird way... '..tostring(kind)..'+'..tostring(code))
    end
  end
end
local function exec(cmd)
  local p = io.popen(cmd, 'r')
  local o = p:read 'a'
  pclose(p)
  return o
end
local function lexec(cmd) return (exec(cmd):gsub('%s+$', '')) end
local function plines(cmd, fmt)
  local p = io.popen(cmd, 'r')
  local f,s,v = p:lines(fmt or 'l')
  return function(...)
    local x = f(...)
    if x == nil then pclose(p) end
    return x
  end, s, v
end
-- local function testexec(cmd)
--   local p = io.popen(cmd, 'r')
--   for _ in p:lines(1024) do end
--   return not not p:close()
-- end

-- Unmagic the magic characters within s, for stitching together patterns.
local function unmagic(s)
  return (s:gsub('[]^$()%%.[*+?-]', '%%%0'))
end

-- Simple command line constructing functions
local function shell(...)
  local function shellw(w)
    if type(w) == 'table' then
      local x = {}
      for i,v in ipairs(w) do x[i] = shellw(v) end
      return table.concat(x, ' ')
    end
    -- We don't handle subshells, so error if we see one.
    assert(not w:find '`', "Subprocess in shell argument "..w)
    local cnt
    w,cnt = w:gsub('[\n$"]', '\\%0')
    return cnt == 0 and not w:find '[\\%s]' and w or '"'..w..'"'
  end
  local function pre(c)
    local prefix = ''
    if c.env then
      local ord = {}
      for k,v in pairs(c.env) do
        assert(k:find '^[%w_]+$', k)
        ord[k] = k..'='..shellw(v):gsub('?', '$'..k)
        table.insert(ord, k)
      end
      table.sort(ord)
      for i,k in ipairs(ord) do ord[i] = ord[k] end
      prefix = prefix..table.concat(ord, ' ')..' '
    end
    return prefix
  end
  local function post(c)
    local postfix = ''
    if c.onlyout then postfix = postfix..' 2>&1' end
    return postfix
  end

  local function command(c)
    local x = {}
    for i,w in ipairs(c) do x[i] = shellw(w) end
    return pre(c)..table.concat(x, ' ')..post(c)
  end
  local pipeline, sequence
  function pipeline(cs)
    if type(cs[1]) == 'string' then return command(cs), true end
    local x = {}
    for i,c in ipairs(cs) do
      local cmd
      x[i],cmd = sequence(c)
      if not cmd then x[i] = '('..x[i]..')' end
    end
    return table.concat(x, ' | ')
  end
  function sequence(cs)
    if type(cs[1]) == 'string' then return command(cs), true end
    local x = {}
    for i,c in ipairs(cs) do x[i] = pipeline(c) end
    return table.concat(x, ' && ')
  end

  return sequence{...}
end
-- local function sexec(...) return exec(shell(...)) end
-- local function slexec(...) return lexec(shell(...)) end
-- local function stestexec(...) return testexec(shell(...)) end
local function slines(...) return plines(shell(...)) end

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
  repeat local cnt
    str,cnt = str:gsub('([`"\'])(.*)', function(d, all)
      local s,o = all:match('^(.-)'..d..'(.*)')
      substrs[#substrs+1] = s
      local id = ('\0%d\0'):format(#substrs)
      substrs[id] = s
      return id..o
    end)
  until cnt == 0

  -- Function to handle arguments and construct bits.
  local bits = {}
  local function handle(flag, pre, arg)
    local h = handlers[flag]
    if h == nil or h == true then bits[#bits+1] = pre..arg  -- Pass through with no fuss
    elseif h == false then return  -- Skip argument
    elseif type(h) == 'string' then bits[#bits+1] = (h:gsub('%%(%d)',{['0']=pre,['1']=arg}))
    elseif type(h) == 'function' then
      local x = h(arg, pre)
      if x == nil then bits[#bits+1] = pre..arg
      elseif x == false then return
      else assert(type(x) == 'string'); bits[#bits+1] = x end
    else error('Unable to handle handler '..tostring(h)) end
  end

  -- Now work through each word and decide what to do with it.
  local cur,cpre,first = nil,nil,true
  for w in str:gmatch '[%g\0]+' do
    repeat local cnt
      w,cnt = w:gsub('\0%d+\0', substrs)
    until cnt == 0
    w = w:gsub('^["\']', ''):gsub('["\']$', '')
    if w:sub(1,1) == '-' then  -- Option argument
      if flags[w:sub(2,2)] then  -- Short option
        local f = flags[w:sub(2,2)]
        if #w > 2 and types[f] == ',' then error('Argument given to non-argument flag: '..w) end
        if #w == 2 and types[f] == ':' then  -- Argument in next word
          cur,cpre = f, '-'..f..' '
        else  -- Argument (if present) in this word
          handle(f, w:sub(1,2), w:sub(3))
        end
      else  -- Must be a long option
        local p,f,e,a = w:match '^(%-%-?)([^=]+)(=?)(.*)'
        f = assert(flags[f], 'Invalid option '..f)
        if e == '=' or types[f] ~= ':' then  -- Argument given in this word
          if types[f] == ',' and e ~= '' then
            error('Argument given to non-argument flag: '..w)
          end
          handle(f, p..f, a)
        else cur,cpre = f,p..f..' ' end -- Argument in next word
      end
    else  -- Non-option argument
      if cur then handle(cur, cpre, w); cur = nil  -- Argument to a flag
      else handle(first, '', w); first = false end  -- Positional arg
    end
  end
  return table.concat(bits, ' ')
end

-- Simple path munching function, takes a path and resolves any ../
local function canonicalize(p, cwd)
  local cbits,ccur = {},1
  for b in (cwd or ''):gmatch '[^/]+' do table.insert(cbits, b) end
  local ups,bits = 0,{}
  for b in p:gmatch '[^/]+' do
    if b == '..' then
      if #bits == 0 then ups = ups + 1 else table.remove(bits) end
    elseif b ~= '.' then  -- Skip over just .
      if #bits == 0 and ups > 0 and cbits[ccur] == b then -- Fold a ../here
        ccur, ups = ccur + 1, ups - 1
      else table.insert(bits, b) end
    end
  end
  local abs = p:sub(1,1) == '/' and ups == 0 and '/' or ''
  return abs..('../'):rep(ups)..table.concat(bits, '/')
end
local function dir(path) return path:gsub('([^/])/*$', '%1/') end
local topcwd = dir(tup.getcwd())
local topdir = dir(lexec 'pwd')

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

local exdeps,exhandled,transforms = {},{},{}
local cfgflags = {}
for f in opts.cfgflags:gmatch '%g+' do
  f = f:gsub('@([^@]+)@', function(ed)
    local path = ed:sub(1,1) ~= '/' and dir(ed)
      or dir(canonicalize(topcwd..'..'..ed))
    local rpath = ed:sub(1,1) == '/' and dir(topdir..ed:sub(2))
      or dir(canonicalize(realbuilddir..ed))
    if not exhandled[path] then
      table.insert(exdeps, path..'<build>')
      transforms[rpath..'dummy'] = path
      exhandled[path] = true
    end
    return rpath..'dummy'
  end)
  table.insert(cfgflags, f)
end
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
    p = canonicalize(realbuilddir..dir(cwd or '')..p)
  end
  local o = {absolute = p}
  for from,to in pairs(transforms) do  -- Try to transform it.
    if p:sub(1,#from) == from then
      if o.root then error(o.root..' & '..to..' match '..p) end
      o.root,o.stem = to,p:sub(#from+1)
      o.path = o.root..o.stem
      if to == srcdir then o.source = true end
      if to == '' then o.build = true end
    end
  end
  return o
end

-- We're going to use a temporary directory, this xpcall ensures we delete it.
local tmpdir, docleansrcdir, finalerror
local function finalize()
  if tmpdir then exec('rm -rf '..tmpdir) end
  if docleansrcdir then exec("cd '"..realsrcdir.."' && git clean -fX") end
end
xpcall(function()
tmpdir = lexec 'mktemp -d':gsub('([^/])/*$', '%1/')
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

-- Step 1: Figure out the build system in use and let it do its thing.
if glob(srcdir..'configure.ac') then  -- Its an automake thing
  docleansrcdir = true
  local env = {
    PATH = topdir..'/build/bin:?',
    AUTOM4TE = topdir..'/build/autom4te-no-cache',
    REALLDD = lexec 'which ldd',
  }
  for l in slines({'autoreconf', '-fis', fullsrcdir, onlyout=true, env=env}) do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
  -- Run configure too while everything is arranged accordingly
  for l in slines({'cd', tmpdir}, {env=env, realsrcdir..'configure',
    '--disable-dependency-tracking', cfgflags, onlyout=true}) do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
elseif glob(srcdir..'CMakeLists.txt') then  -- Negligably nicer CMake thing
  for l in slines({'cmake', '-G', 'Unix Makefiles', cfgflags,
    '-S', fullsrcdir, '-B', tmpdir}) do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
else error("Unable to determine build system!") end

-- Step 2: Have GNU make cough up its own database with all the rules, and
-- construct a global view of the world with all the bits.
local makevarpatt = '[%w_<>@.?%%^*+-]+'
local parsemakecache = {}
local ruleset = {templates={}, normal={}}
local function parsemakefile(fn, cwd)
  cwd = dir(cwd or '')
  if parsemakecache[cwd..fn] then
    assert(parsemakecache[cwd..fn] == cwd, 'Makefile '..cwd..fn..' parsed under different working dirs!')
    return
  end
  parsemakecache[cwd..fn] = cwd

  -- A simple single-state machine for parsing.
  local state = 'preamble'
  local vars,cur = {},nil
  for l in slines{
    {{'cat', tmpdir..cwd..fn}, {'printf', 'dummyZXZ:\\n\\n'}},
    {'env','-i', 'make', '-C', tmpdir..cwd, '-pqsrRf-', 'dummyZXZ'}
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
        cur = {vars = vars, cwd =cwd}
        cur.outs, cur.deps = l:match '^(.-):%s*(.*)$'
        assert(not cur.outs:find '%$' and not cur.deps:find '%$', l)
        local x = {}
        for p in cur.outs:gmatch '%g+' do
          if not cur.target then cur.target = p end
          p = path(p, cwd).path
          if not p then x = false; break end
          if p:find '%%' then cur.implicit = true end
          table.insert(x, p)
        end
        if not x then cur = nil else
          cur.outs = x
          local y = {}
          for p in cur.deps:gmatch '%g+' do
            p = path(p, cwd).path
            if p then table.insert(y, p) end
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
              if not rs[p] then rs[p] = {} end
              rs[p][cur] = true
            end
          else  -- Normal rule, file output (in theory)
            local rs = ruleset.normal
            for _,p in ipairs(cur.outs) do
              if rs[p] then  -- Another rule already placed down.
                if #rs[p] == 0 then  -- Other rule is dep-only. Take its deps.
                  table.move(rs[p].deps, 1,#rs[p].deps, #cur.deps+1, cur.deps)
                  rs[p] = cur
                elseif #cur == 0 then  -- I'm dep-only, append my new deps
                  table.move(cur.deps, 1,#cur.deps, #rs[p].deps+1, rs[p].deps)
                else  -- Two recipes for the same file, error.
                  if not cur[1]:find '$%(MAKE%)'  -- For autotools
                    and not cur[1]:find '%-%-check%-build%-system'  -- For CMake
                    and not rs[p][1]:find '$%(MAKE%)'  -- For CMake too
                  then
                    print(table.unpack(rs[p].outs))
                    print(table.unpack(rs[p]))
                    print(table.unpack(cur.outs))
                    print(table.unpack(cur))
                    error(cwd..'| '..p)
                  end
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
end

-- Step 3: Hunt down the files that we need to generate, and find or construct
-- a rule to generate them. Also do some post-processing for expanding vars.
local function findrule(fn)
  local r = ruleset.normal[fn.path]
  if not r then
    -- First check if the file actually exists already.
    if glob(fn.path) or glob(fn.stem) then
      print('File '..fn.path..' already exists!')
      return
    end

    -- If we haven't found anything by now, error.
    assert(r, 'No rule to generate '..fn.path..'!')
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
      return 'XXXlibdwfl.a'  -- luacheck: no max line length
    elseif cmd == '$(AR) t ../libdwelf/libdwelf.a' then
      return 'XXXlibdwelf.a'
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
  r.vars = setmetatable({
    ['@'] = r.outs[1], ['<'] = r.deps[1] or '', ['*'] = r.stem or '',
    ['^'] = table.concat(r.deps, ' '),
  }, {__index=r.vars})
  function r.expand(s) return expand(s, r.vars) end
  r.ex = {}
  for i,c in ipairs(r) do r.ex[i] = r.expand(c:gsub('^[@-]*', '')) end

  return r
end

-- Step 4: For some file, analyze the rule that generates it and determine its
-- properties and figure out the core recipe command for translation.
-- The return is the path to use to reference to the file for build purposes.
local translations = {}
local function make(fn)
  if type(fn) == 'string' then fn = path(fn) end
  local r = findrule(fn)
  if not r then return fn.path end  -- We don't need to do anything.
  if r.made then return r.made end  -- Don't duplicate work if at all possible.
  if r.antirecurse then return end  -- When just scanning, don't recurse.

  -- First make sure all the deps have been made
  local deps = {}
  for i,d in ipairs(r.deps) do deps[i] = make(d) end

  -- Next go through and identify every command, and collect together some
  -- info to pass to the specific translator.
  local info = {out = fn.path}
  local handled,printout = {}, cfgbool 'DEBUG_MAKE_TRANSLATION'
  for i,c in ipairs(r) do
    local ex = r.ex[i]
    local function check(tf, note, err)
      if not tf then handled[i],info.error = note or 'error', err or '#'..i end
    end
    if c:find '$%(ACLOCAL%)' then handled[i] = 'Autotools: call to aclocal'
    elseif c:find '$%(AUTOHEADER%)' then handled[i] = 'Autotools: call to autoheader'
    elseif c:find '$%(AUTOCONF%)' then handled[i] = 'Autotools: call to autoconf'
    elseif c:find '$%(SHELL%) %./config%.status' then handled[i] = 'Autotools: call to config.status'
    elseif c:find '^@?rm %-f' then
      handled[i] = 'Make: force removal of file'
      check(not info.kind)
    elseif c == 'touch $@' then handled[i] = 'Make: touch of output file'
    elseif c:find '^@?test %-f $@ ||' then
      handled[i] = 'Autotools: timestamp management'
      check(c:find 'stamp%-h1')
    elseif c:find '^$%(CMAKE_COMMAND%)' then
      if c:find '%-E cmake_progress_start' then handled[i] = 'CMake: progress bar markers'
      elseif c:find '%-%-check%-build%-system' then handled[i] = 'CMake: makefile regeneration'
      else printout = true end
    elseif c:find '^$%(MAKE%)' then
      local mf,cd,targs = nil,nil,{}
      getopt(ex, 'no-print-directory,f:', {
        f = function(f) mf = f end,
        [false] = function(t) table.insert(targs, t) end,
      })
      mf = mf or 'Makefile'
      cd = r.cwd..dir(cd or '')
      handled[i] = 'Make: '..(mf and '('..mf..') ' or '')
        ..'@'..(#cd > 0 and cd or './')..' '..table.concat(targs, ' ')
      -- Unlike in other cases, we handle this directly here. Saves a call.
      assert(not info.kind or info.kind == 'make'); info.kind = 'make'
      parsemakefile(mf, cd)
      r.antirecurse = true
      for _,t in ipairs(targs) do make(cd..t) end
      r.antirecurse = nil
    else printout = true end
  end
  if info.error ~= nil then printout = true end

  -- If anything had troubles, print out a note to the output on the subject.
  if printout and #r > 0 then
    local function p(x, y) return x..(x ~= y and ' ('..y..')' or '') end
    print(p(info.out, fn.path)..' | '..(#r.cwd > 0 and r.cwd or '.')..':')
    for i,d in ipairs(deps) do print('  + '..p(d, r.deps[i])) end
    for i,c in ipairs(r) do
      if handled[i] then print('  # '..handled[i]) end
      print('  '..(handled[i] and '^' or '$')..' '..c)
      if not handled[i] then print('  % '..r.ex[i]) end
    end
    if info.kind then
      local b = {}
      for k,v in pairs(info) do table.insert(b, k..'='..tostring(v)) end
      b = table.concat(b, ', ')
      print('  > '..info.kind..(translations[info.kind] and '()' or '')..' {'..b..'}')
    end
    print()
  end
  if info.error ~= nil then error(info.error) end
  r.made = info.out
  return r.made
end

-- Step N: Fire it off!
parsemakefile 'Makefile'
make 'all'

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
