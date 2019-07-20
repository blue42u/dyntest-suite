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
local function testexec(cmd)
  local p = io.popen(cmd, 'r')
  for _ in p:lines(1024) do end
  return not not p:close()
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
local cfgflags = opts.cfgflags:gsub('%s*\n%s*', ' '):gsub('^%s*', '')
  :gsub('%s*$', ''):gsub('@([^@]+)@', function(ed)
    local path = ed:sub(1,1) ~= '/' and dir(ed)
      or dir(canonicalize(topcwd..'..'..ed))
    local rpath = ed:sub(1,1) == '/' and dir(topdir..ed:sub(2))
      or dir(canonicalize(realbuilddir..ed))
    if not exhandled[path] then
      table.insert(exdeps, path..'<build>')
      transforms[path..'dummy'] = path
      transforms[rpath..'dummy'] = path
      exhandled[path] = true
    end
    return rpath..'dummy'
  end)

-- We're going to use a temporary directory, this xpcall ensures we delete it.
local tmpdir, docleansrcdir, finalerror
local function finalize()
  if tmpdir then exec('rm -rf '..tmpdir) end
  if docleansrcdir then exec("cd '"..realsrcdir.."' && git clean -fX") end
end
xpcall(function()
tmpdir = lexec 'mktemp -d':gsub('([^/])/*$', '%1/')

-- Helper for interpreting tup.glob output, at least for what we do.
local function glob(s)
  local x = tup.glob(s)
  return #x > 0 and x
end

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
  local env = 'PATH="'..topdir..'"/build/bin:"$PATH" '
  env = env.. 'AUTOM4TE="'..topdir..'"/build/autom4te-no-cache '
  for l in plines(env..'autoreconf -fis '..fullsrcdir..' 2>&1') do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
  -- Run configure too while everything is arranged accordingly
  for l in plines("cd '"..tmpdir.."' && "..env.."'"..realsrcdir.."/configure'"
    ..' --disable-dependency-tracking '..cfgflags..' 2>&1') do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
elseif glob(srcdir..'CMakeLists.txt') then  -- Negligably nicer CMake thing
  for l in plines("cmake -S '"..fullsrcdir.."' -B '"..tmpdir.."' "..cfgflags) do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
else error("Unable to determine build system!") end

-- Step 2: Have GNU make cough up its own database with all the rules
-- Parse the output and generate a table with all the bits.
local function parsemakefile(fn, cwd)
  fn,cwd = tmpdir..fn, tmpdir..(cwd or '')
  local cmd = "(cat '"..fn.."'; printf 'dummyZXZ:\\n\\n') | "
    .."make -C '"..cwd.."' -pqsrRf- dummyZXZ"
  local cnt = 0
  for l in plines(cmd) do cnt = cnt + 1
  end
  print(cnt)
end

-- Step N: Fire it off!
parsemakefile('Makefile', '.')

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
