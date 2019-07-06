#!/usr/bin/env lua5.3

-- Somewhat automatic conversion from Makefiles to Tup rules.
-- Usage: ./make.lua <path/to/source> <path/to/install>
local srcdir,instdir = ...  -- luacheck: no unused

-- Debugging function for outputting info to stderr.
local function dbg(...)
  local t = {...}
  for i,v in ipairs(t) do t[i] = tostring(v) end
  io.stderr:write(table.concat(t, '\t')..'\n')
end

-- Proper close for popen'd files that errors when the subprocess errors.
local function pclose(f)
  local ok,how,why = f:close()
  if not ok then
    if how == 'exit' then error('Subprocess exited with '..why)
    elseif how == 'signal' then error('Subprocess terminated by signal '..why)
    else error('Subprocess terminated in a weird way, is this Lua 5.3?') end
  end
end
local function exec(cmd)
  local f = io.popen(cmd, 'r')
  local o = f:read 'a'
  pclose(f)
  return o
end

-- Unmagic the magic characters within s, for stitching together patterns.
local function unmagic(s)
  return (s:gsub('[]^$()%%.[*+?-]', '%%%0'))
end

-- We often will need to check for files in the filesystem to know whether a
-- file is a source file or not (implicit rules). This does the actual check.
local insrc
do
  local rspatt = '^'..unmagic(exec('realpath '..srcdir):gsub('%s*$', ''))
  local dircache = {}
  function insrc(fn)
    fn = fn:gsub('//+', '/'):gsub('%./', '')
    local d,f = fn:match '^(.-)([^/]+)$'
    d = ('/'..d..'/'):gsub('//+', '/')
    if d:find(rspatt) then return srcdir..d:match(rspatt..'(.*)')..f end
    if dircache[d] then return dircache[d][f] end

    local p = io.popen('find '..srcdir..d..' -type f -maxdepth 1', 'r')
    local c = {}
    for l in p:lines() do c[l:match '[^/]+$'] = l end
    pclose(p)
    dircache[d] = c
    return c[f]
  end
end

-- We let make parse the Makefiles for us, and cache the outputs in a little
-- table to make things faster. Argument is the path to the Makefile.
local makecache = {}
local function makeparse(makefn)
  makefn = makefn:gsub('//+', '/'):gsub('%./', '')
  if makecache[makefn] then return makecache[makefn] end

  local p = io.popen(
    "(cat "..makefn.."; printf '\\nXXdonothing:\\n.PHONY: XXdonothing\\n') |"
    .."make -pqsrRf- XXdonothing")
  local c = {vars={}, implicit={}, normal={}}

  -- We use a simple single-state machine, to triple-check the database output.
  local state = 'preamble'
  local crule
  for l in p:lines() do
    if state == 'preamble' then
      if l == '# Variables' then state = 'vars' end
      assert(l:sub(1,1) == '#' or #l == 0, l)
    elseif state == 'vars' then
      if l == '# Implicit Rules' then state = 'outsiderule' else
        if #l > 0 and l:sub(1,1) ~= '#' then
          local k,v = l:match '^(%g+) :?= (.*)$'
          assert(k and v, l)
          c.vars[k] = v
        end
      end
    elseif state == 'outsiderule' then
      if l:find '^%g+:' then
        state = 'rulepreamble'
        local n,d = l:match '^(%g-):(.*)'
        dbg(n, d)
        assert(n and d, l)
        crule = {name=n, depstring=d, implicit=not not n:find '%%'}
      else
        assert(#l == 0 or l:sub(1,1) == '#')
      end
    elseif state == 'rulepreamble' then
      if l:sub(1,1) ~= '#' then state = 'rule' else
        if l:find '^# Phony target' then
          crule.phony = true
        end
      end
    end
    if state == 'rule' then
      if #l == 0 then
        state = 'outsiderule'
        assert(#crule == 0 or crule[#crule]:sub(-1) ~= '\\')
        if crule.implicit then c.implicit[crule] = crule.name else
          assert(not c.normal[crule.name], crule.name)
          c.normal[crule.name] = crule
        end
      else
        assert(l:sub(1,1) == '\t')
        if #crule > 0 and crule[#crule]:sub(-1) == '\\' then
          crule[#crule] = crule[#crule]:sub(1,-2):gsub('%s*$', '')
            ..' '..l:gsub('^%s*', '')
        else table.insert(crule, l:sub(2)) end
      end
    end
  end
  assert(state == 'outsiderule', 'Database ended in wrong state!')

  pclose(p)
  makecache[makefn] = c
  return c
end
