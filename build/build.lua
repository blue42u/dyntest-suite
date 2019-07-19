-- luacheck: std lua53, new globals tup

-- The main script for building things. Handles everything from CMake to Libtool
-- and the antiparallelism in Elfutils.

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

-- We're going to use a temporary directory, this xpcall ensures we delete it.
local tmpdir, finalerror
local function finalize() if tmpdir then exec('rm -rf '..tmpdir) end end
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

-- Step 0: Gather info about where all the files actually are from here.
print(CFG_FLAGS)
local fullsrcdir = tostring(SRCDIR):gsub('([^/])/*$', '%1/')  -- luacheck: new globals SRCDIR
local srcdir = tup.getcwd()..'/../'..fullsrcdir
local realsrcdir = lexec("realpath '"..fullsrcdir.."'")

-- Step 1: Figure out the build system in use and let it do its thing.
if glob(srcdir..'configure.ac') then  -- Its an automake thing
  -- Autoreconf works in the source directory, but since we're not actually in
  -- the FUSE box we can't prevent it from messing stuff up. So we check the
  -- output and move anything it makes into the tmpdir for later processing.
  local tomv = {}
  for l in plines('autoreconf -fis '..fullsrcdir..' 2>&1') do
    tomv[#tomv+1] = l:match "installing '(.*)'"
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end
  -- Run configure too while everything is arranged accordingly
  local c = tostring(CFG_FLAGS)  -- luacheck: new globals CFG_FLAGS
  for l in plines("cd '"..tmpdir.."' && '"..realsrcdir.."/configure' "..c..' 2>&1') do
    if cfgbool 'DEBUG_CONFIGURE' then print(l) end
  end

  -- Now move everything that we touched out and into the tmpdir.
  for _,f in ipairs(tomv) do
    local d = f:match '^(.-)[^/]+$'
    exec("mkdir -p '"..tmpdir..d.."'")
    exec("mv '"..fullsrcdir..f.."' '"..tmpdir..d.."'")
  end

  -- Autoreconf also makes a bunch of junk otherwise. Move that over too.
  for _,f in ipairs{'aclocal.m4', 'config.h.in', 'configure'} do
    exec("mv '"..fullsrcdir..f.."' '"..tmpdir.."'")
  end
  exec('rm -rf \''..fullsrcdir..'autom4te.cache\'')

  -- The Makefile.in's are trickier, we use a subprocess instead of the glob.
  for _,d in ipairs{
    '.', 'backends', 'config', 'lib', 'libasm', 'libcpu', 'libdw', 'libdwelf',
    'libdwfl', 'libebl', 'libelf', 'm4', 'src', 'tests',
  } do
    if testexec("stat '"..fullsrcdir..d.."/Makefile.am' 2>&1") then
      exec("mv '"..fullsrcdir..d.."/Makefile.in' '"..tmpdir..d.."'")
    end
  end
elseif glob(srcdir..'CMakeLists.txt') then  -- Negligably nicer CMake thing
  local c = tostring(CFG_FLAGS)  -- luacheck: new globals CFG_FLAGS
  for l in plines("cmake -S '"..fullsrcdir.."' -B '"..tmpdir.."' "..c) do
    print(l)
  end
end

-- Step 2: Have GNU make cough up its own database with all the rules
-- Parse the output and generate a table with all the bits.
local function parsemakefile(fn, cwd)
  fn,cwd = tmpdir..fn, tmpdir..(cwd or '')
  local cmd = "(cat '"..fn.."'; printf 'dummyZXZ:\\n\\n') | "
    .."make -C '"..cwd.."' -pqsrRf- dummyZXZ"
  for l in plines(cmd) do
    print(l)
  end
end


-- Step N: Fire it off!
-- parsemakefile('Makefile', '.')

-- Error with a magic value to ensure the thing gets finalized
error(finalize)
end, function(err)
  finalize()
  if err ~= finalize then
    finalerror = debug.traceback(tostring(err), 2)
  end
end)
if finalerror then error(finalerror) end
