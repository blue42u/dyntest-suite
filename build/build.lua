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
local parsemakecache = {}
local ruleset = {templates={}, normal={}}
local function parsemakefile(fn, cwd)
  cwd = dir(cwd or ''); assert(not fn:find '/')
  if parsemakecache[cwd..fn] then return end
  parsemakecache[cwd..fn] = true

  -- A simple single-state machine for parsing.
  local makevarpatt = '[%w_<>@.?%%^*+-]+'
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
        cur = {vars = vars}
        cur.outs, cur.deps = l:match '^(.-):%s*(.*)$'
        assert(not cur.outs:find '%$' and not cur.deps:find '%$', l)
        local x = {}
        for p in cur.outs:gmatch '%g+' do
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
                if #rs[p] == 0 then  -- Other rule is dep-only. Overwrite.
                  assert(#rs[p].deps == 0, p)
                  rs[p] = cur
                elseif #cur == 0 then  -- I'm dep-only, don't overwrite
                  assert(#cur.deps == 0, p)
                else  -- Two recipes for the same file, error.
                  if not cur[1]:find '$%(MAKE%)' then  -- Handle autotools bits
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
          table.insert(cur, l:sub(2))
        end
      end
    end
  end
end

-- Step 3: Hunt down the files that we need to generate, and find or construct
-- a rule to generate them. Also do some post-processing for expanding vars.
local function findrule(fn)
  if type(fn) == 'string' then fn = path(fn) end
  local r = ruleset.normal[fn.path]
  if not r then
    -- First check if the file actually exists already.
    if glob(fn.path) or glob(fn.stem) then
      print('File '..fn.path..' already exists!')
      return
    end

    -- If we haven't found anything by now, error.
    assert(r, fn.path)
  end

  print(table.unpack(r.outs))
  print(table.unpack(r.deps))
  print(table.unpack(r))
end

-- Step N: Fire it off!
parsemakefile 'Makefile'
findrule 'all'

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
