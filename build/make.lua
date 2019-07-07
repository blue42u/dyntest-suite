#!/usr/bin/env lua5.3
-- luacheck: std lua53

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

local insrc,pclean
do
  local rspatt = '^'..unmagic(exec('realpath '..srcdir):gsub('%s*$', ''))..'(.*)'
  local ripatt = '^'..unmagic(exec('realpath '..instdir):gsub('%s*$', ''))..'(.*)'
  local dircache = {}
  -- We often will need to check for files in the filesystem to know whether a
  -- file is a source file or not (implicit rules). This does the actual check.
  function insrc(fn)
    fn = fn:gsub('//+', '/'):gsub('%./', '')
    local d,f = fn:match '^(.-)([^/]+)$'
    d = ('/'..d..'/'):gsub('//+', '/')
    if d:find(rspatt) then return srcdir..d:match(rspatt)..f end
    if dircache[d] then return dircache[d][f] end

    local p = io.popen('find '..srcdir..d..' -type f -maxdepth 1 2> /dev/null', 'r')
    local c = {}
    for l in p:lines() do c[l:match '[^/]+$'] = l end
    p:close()
    dircache[d] = c
    return c[f]
  end
  -- Paths sometimes will reference the source directories. This cleans a
  -- potental path to adjust references accordingly.
  function pclean(path)
    if path:find(rspatt) then return srcdir..path:match(rspatt)
    elseif path:find(ripatt) then return instdir..path:match(ripatt)
    else return path end
  end
end

local makevarpatt = '[%w_<>@.?%%^*+]+'

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
          local k,v = l:match('^('..makevarpatt..') :?= (.*)$')
          assert(k and v, l)
          c.vars[k] = v
        end
      end
    elseif state == 'outsiderule' then
      if l:find '^%g+:' then
        state = 'rulepreamble'
        local n,d = l:match '^(%g-):(.*)'
        assert(n and d, l)
        crule = {name=n, depstring=d, implicit=not not n:find '%%'}
      else
        assert(#l == 0 or l:sub(1,1) == '#', l)
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

-- After a rule is parsed above, there is a lot of postprocessing that can be
-- done (variable expansion and implicit rule search), but there is a lot of
-- Make that is far more complex than we want to handle. So we only do such
-- processing on-demand when its needed.
local function makerule(makefn, targ)
  local rs = makeparse(makefn)
  local r = rs.normal[targ]
  if not r or #r == 0 then
    if insrc(targ) then  -- Its a source file, so return the real name
      return insrc(targ)
    end

    -- Find the most applicable implicit rule for our purposes.
    local match,stem
    for ir in pairs(rs.implicit) do
      local p = unmagic(ir.name:gsub('%%', ':;!')):gsub(':;!', '(.+)')
      local s = targ:match(p)
      if s and (not match or #match.name <= #ir.name) then
        match,stem = ir,s
      end
    end

    if match then
      -- Instance the implicit rule to get the unprocessed final recipe
      r = {name=targ, implicit=false, stem=stem}
      r.depstring = match.depstring:gsub('%%', stem)
      rs[targ] = r
    end
    -- If it doesn't match, we'll just pretend its a pseudo-phony and move on.
    assert(r, targ)
  end
  if r.postprocessed then return targ,r end
  r.postprocessed = true

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

  -- Now we expand the depstring and split it by word to get the targets.
  r.deps = {}
  for w in expand(r.depstring, rs.vars):gmatch '%g+' do table.insert(r.deps, w) end

  -- And then expand the command strings to get the actual commands
  local allvars = setmetatable({
    ['@'] = targ or '', ['<'] = r.deps[1] or '', ['*'] = r.stem or '',
    ['^'] = table.concat(r.deps, ' '),
  }, {__index=rs.vars})
  r.ex = {}
  for _,l in ipairs(r) do
    table.insert(r.ex, (expand(l, allvars):gsub('^[-@]*', '')))
  end

  function r.expand(s) return expand(s, allvars) end

  return targ,r
end

local AMrecurse = ([[@fail=; if $(am__make_keepgoing); then failcom='fail=yes'; \
else failcom='exit 1'; fi; dot_seen=no; target=`echo $@ | sed s/-recursive//`; \
case "$@" in distclean-* | maintainer-clean-*) list='$(DIST_SUBDIRS)' ;; *) \
list='$(SUBDIRS)' ;; esac; for subdir in $$list; do echo "Making $$target in \
$$subdir"; if test "$$subdir" = "."; then dot_seen=yes; local_target=\
"$$target-am"; else local_target="$$target"; fi; ($(am__cd) $$subdir && \
$(MAKE) $(AM_MAKEFLAGS) $$local_target) || eval $$failcom; done; if test \
"$$dot_seen" = "no"; then $(MAKE) $(AM_MAKEFLAGS) "$$target-am" || exit 1; \
fi; test -z "$$fail"]]):gsub('\\\n', '')

-- This is the actual recursive make call. We assume that the Makefiles are
-- written to actually work and aren't naturally recursive.
local makecache2 = {}
local realmake
local function make(f, t)
  if makecache2[f] and makecache2[f][t] then return makecache2[f][t] end
  makecache2[f] = makecache2[f] or {}
  local o = realmake(f, t)
  makecache2[f][t] = o
  return o
end
function realmake(makefn, targ)
  local name, rule = makerule(makefn, targ)
  if not rule then return name end  -- Source file, don't do anything
  local realname = pclean(name)
  local printout,trules = false,{}
  local deps = {}
  for i,d in ipairs(rule.deps) do deps[i] = make(makefn, d) end

  for idx,cmd in ipairs(rule) do
    local exc = rule.ex[idx]
    local tr = nil
    local AM,CM = '# Automake configure ', '# CMake configure '
    -- Automake-generated rules and commands.
    if cmd:find '$%(ACLOCAL%)' then tr = AM..'(aclocal)'
    elseif cmd:find '$%(AUTOHEADER%)' then tr = AM..'(autoheader)'
    elseif cmd:find '$%(AUTOCONF%)' then tr = AM..'(autoconf)'
    elseif cmd:find '$%(SHELL%) %./config%.status' then tr = AM..'(config.status)'
    elseif cmd:find '$%(MAKE%) $%(AM_MAKEFLAGS%) am%-%-refresh' then tr = AM..'(refresh)'
    elseif exc:find '^test %-f config%.h' then tr = AM..'('..exc:match '|| (.*)'..')'
    elseif cmd == 'touch $@' then tr = ''
    elseif exc:find '^rm %-f' then tr = ''
    -- CMake-generated rules and commands.
    elseif cmd:find '^$%(CMAKE_COMMAND%) %-S' then tr = CM..'(check build sys)'
    elseif cmd:find '^$%(CMAKE_COMMAND%) %-E cmake_progress' then tr = CM..'(progress start)'
    elseif cmd:find '^@$%(CMAKE_COMMAND%) %-E cmake_echo' then tr = CM..'(progress bar)'
    elseif cmd:find '$%(CMAKE_COMMAND%) %-E cmake_depends' then tr = CM..'(dependency scan)'
    elseif cmd:find '^@$%(CMAKE_COMMAND%) %-E touch_nocreate' then tr = CM..'(touch)'
    -- Recursive Make calls
    elseif exc:find '^make%s' then
      local fn,targs = makefn,{}
      for w in exc:match '^make%s+(.*)':gmatch '%g+' do
        if w:sub(1,1) == '-' then
          if w:sub(1,2) ~= '--' and w:find 'f' then
            fn = nil
          end
        elseif fn then table.insert(targs, w)
        else fn = w end
      end
      for _,t in ipairs(targs) do make(fn, t) end
      tr = '# make '..(fn == makefn and '' or '-f '..fn..' ')
        ..table.concat(targs, ' ')
    elseif cmd:find '^@fail=;' then
      assert(cmd == AMrecurse, cmd)
      assert(not (targ:find '^distclean%-' or targ:find 'maintainer%-clean%-'))
      local target = targ:gsub('%-recursive$', '')
      for s in rule.expand('$(SUBDIRS)'):gmatch '%g+' do
        assert(s ~= '.')
        make(makefn:gsub('[^/]+$', unmagic(s)..'/%0'), target)
      end
      make(makefn, target..'-am')
      tr = AM..'(recursive make call)'
    end
    if tr then
      if tr:sub(1,1) == ':' then print(tr)
      elseif tr == '' then tr = '# Skipped: '..exc end
      trules[idx] = tr
    end
  end

  for i in ipairs(rule) do if not trules[i] then printout = true; break end end
  if printout then
    dbg(makefn..' '..realname..': '..table.concat(deps, ' '))
    for i,c in ipairs(rule) do
      if trules[i] then dbg('  '..trules[i])
      else dbg('  $ '..rule.ex[i]); dbg('  % '..c) end
    end
  end
  return realname
end

make('Makefile', 'install')
