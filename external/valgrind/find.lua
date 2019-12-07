-- luacheck: std lua53, no global (Tup-lua)

if not externalProjects then externalProjects = {} end
externalProjects.valgrind = {}

BUILD_VALGRIND = 'n'  -- Let's be hopeful
local function useours()
  BUILD_VALGRIND = 'y'
  VALGRIND_CMD = 'VALGRIND_LIB='..tup.getcwd()..'/install/lib/valgrind '
    ..tup.getcwd()..'/install/bin/valgrind'
  VALGRIND_MS_PRINT = tup.getcwd()..'/install/bin/ms_print'
  externalProjects.valgrind = nil
end

-- First find the headers. We need them.
if subp.testexec 'pkg-config --exists valgrind' then
  -- pkg-config knows, let's trust it first.
  local incdir = subp.lexec 'pkg-config --cflags valgrind':match '%-I%s*(%S+)'
  local rdir = incdir:match '^(.+)include/valgrind/*$'
  if not rdir then return useours() end
  externalProjects.valgrind.rootDir = rdir:gsub('/*$', '/')
elseif subp.testexec 'stat /usr/include/valgrind/valgrind.h 2> /dev/null' then
  -- It seems to be on a system path, we can use that.
  if not subp.testexec 'stat /usr/include/valgrind/helgrind.h 2> /dev/null' then
    print('WARNING: valgrind.h present but helgrind.h is not!')
    return useours()
  end
  if not subp.testexec 'stat /usr/include/valgrind/drd.h 2> /dev/null' then
    print('WARNING: valgrind.h present but helgrind.h is not!')
    return useours()
  end
  externalProjects.valgrind.rootDir = '/usr/'
else return useours() end

-- Next check that valgrind is on the PATH and has a fairly recent version.
if not subp.testexec 'valgrind --version' then return useours() end
local version = subp.lexec 'valgrind --version'
local vM,vm,_ = version:match '^valgrind%-(%d+)%.(%d+)%.(%d+)$'
if not vM then
  print('WARNING: Valgrind found but giving a weird version: '..version)
  return useours()
end
if tonumber(vM) < 3 then return useours() end
if tonumber(vm) < 14 then return useours() end
VALGRIND_CMD = 'valgrind'

-- Last, verify that ms_print is on the path. Because we need that too.
if not subp.testexec 'which ms_print' then return useours() end
VALGRIND_MS_PRINT = 'ms_print'
