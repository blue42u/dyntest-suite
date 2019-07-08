#!/usr/bin/env lua5.3
-- luacheck: std lua53

-- Somewhat automatic conversion from Makefiles to Tup rules.
-- Usage: ./make.lua <path/to/source> <path/to/install> <path/of/tmpdir> <extra deps>
local srcdir,instdir,group,tmpdir,exdeps,transforms = ...

-- Debugging function for outputting info to stderr.
local function dbg(...)
  local t = {...}
  for i,v in pairs(t) do t[i] = tostring(v) end
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

-- Get a canonical path for the given path
local function canonicalize(p)
  local abs = p:sub(1,1) == '/'
  local pre,real = {},{}
  for b in p:gmatch '[^/]+' do
    if b == '..' then
      if #real > 0 then real[#real] = nil else table.insert(pre, b) end
    elseif b ~= '.' then table.insert(real, b) end
  end
  if abs and #pre > 0 then abs = false end  -- Fake abs path
  table.move(real, 1,#real, #pre+1, pre)
  if not abs and #pre == 0 then return '.' end
  return (abs and '/' or '')..table.concat(pre, '/')
end

-- A partially-correct implementation of getopt, for command line munging.
-- Opts is a table with ['flag'] = 'simple' | 'arg', or an optstring
local function gosub(s, opts, repl)
  if type(opts) == 'string' then
    local o = {}
    for f,a in opts:gmatch '([^,:]+)([,:])' do
      o[f] = a == ':' and 'arg' or 'simple'
    end
    opts = o
  end

  local function munch(flag, arg, prefix)
    local r = repl[flag]
    if r then
      if type(r) == 'function' then return (r(arg, prefix)) end
      if type(r) == 'table' and r[arg] then return prefix..r[arg] end
      if type(r) == 'string' then
        return (r:gsub('%%0', prefix):gsub('%%1', (arg or ''):gsub('%%', '%%%%')))
      end
    end
    if r == false then return '' end
    return prefix..(arg or '')
  end
  local bits = {}
  local cur,curfix
  local quoted
  for rw in s:gmatch '%g+' do
    local w = rw
    if quoted then quoted, w = quoted..' '..w, nil end
    if #rw:gsub('[^"]+', '') & 1 == 1 then  -- Odd number of "'s, toggle quoted
      quoted,w = w,quoted
    end
    if w then  -- Parse the word
      if cur then
        table.insert(bits, munch(cur, w, curfix))
        cur,curfix = nil,nil
      else
        if w:sub(1,1) == '-' then  -- Start of a new flag
          assert(w:sub(1,2) ~= '--', "Can't handle real long options yet!")
          if opts[w:sub(2,2)] then  -- Simple flag
            local f,a = w:sub(2,2),w:sub(3)
            if #a > 0 then  -- Argument in this word, munch and continue
              assert(opts[f] == 'arg', "Can't handle multiple short options yet!")
              table.insert(bits, munch(f, a, '-'..f))
            elseif opts[w:sub(2,2)] == 'simple' then  -- That's all folks
              table.insert(bits, munch(f, nil, '-'..f))
            else  -- Argument in next word, mark for consumption
              cur,curfix = f,'-'..f..' '
            end
          else  -- Must be a long word. Break at the = if possible
            local f,e,a = w:sub(2):match '([^=]+)(=?)(.*)'
            assert(opts[f], "No option "..f..' for '..('%q'):format(s)..'!')
            if e == '=' then  -- There was an =, argument in this word.
              assert(opts[f] == 'arg', "Argument given to non-arg longer flag!")
              table.insert(bits, munch(f, a, '-'..f..'='))
            elseif opts[f] == 'simple' then  -- That's all folks
              table.insert(bits, munch(f, nil, '-'..f))
            else  -- Argument is in next word, mark for consumption
              cur,curfix = f,'-'..f..' '
            end
          end
        else  -- Non-option word. Format with repl[false]
          table.insert(bits, munch(false, w, ''))
        end
      end
    end
  end
  return table.concat(bits, ' ')
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
    if d:find(rspatt) then return canonicalize(srcdir..d:match(rspatt)..f) end
    d = canonicalize('/'..d..'/')
    if dircache[d] then return dircache[d][f] end

    local p = io.popen('find '..srcdir..d..' -type f -maxdepth 1 2> /dev/null', 'r')
    local c = {}
    for l in p:lines() do c[l:match '[^/]+$'] = l end
    p:close()
    dircache[d] = c
    return c[f]
  end
  local patts = {}
  for p,v in transforms:gmatch '(%g+)=(%g+)' do
    patts['^'..unmagic(p)..'(.*)'] = v
  end
  -- Paths sometimes will reference the source directories. This cleans a
  -- potental path to adjust references accordingly.
  function pclean(path)
    if path:find(rspatt) then return canonicalize(srcdir..path:match(rspatt)) end
    if path:find(ripatt) then return canonicalize(instdir..path:match(ripatt)) end
    local res
    for p,d in pairs(patts) do if path:find(p) then
      assert(not res, "Multiple patts match "..('%q'):format(path).."!")
      res = canonicalize(d..path:match(p))
    end end
    return res or canonicalize(path)
  end
end

local makevarpatt = '[%w_<>@.?%%^*+]+'

-- We let make parse the Makefiles for us, and cache the outputs in a little
-- table to make things faster. Argument is the path to the Makefile.
local makecache = {}
local function makeparse(makefn, cwd)
  makefn = canonicalize(makefn)
  local id = cwd..':'..makefn
  if makecache[id] then return makecache[id] end

  local db = nil
  -- db = ' | tee /tmp/q_'..cwd:gsub('/','_')..'.'..makefn:gsub('/','_')
  local p = io.popen("cd ./"..cwd.." && "
    .."(cat "..makefn.."; printf '\\nXXdonothing:\\n.PHONY: XXdonothing\\n') | "
    .."make -pqsrRf- XXdonothing"..(db or ''))
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
      if l:find '^[^#%s].*:' then
        state = 'rulepreamble'
        local n,d = l:match '^(%g+).-:(.*)'
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
        assert(l:sub(1,1) == '\t', l)
        if #crule > 0 and crule[#crule]:sub(-1) == '\\' then
          crule[#crule] = crule[#crule]:sub(1,-2):gsub('%s*$', '')
            ..' '..l:gsub('^%s*', '')
        else table.insert(crule, l:sub(2)) end
      end
    end
  end
  pclose(p)
  assert(state == 'outsiderule', 'Database ended in wrong state!')

  makecache[makefn] = c
  return c
end

-- After a rule is parsed above, there is a lot of postprocessing that can be
-- done (variable expansion and implicit rule search), but there is a lot of
-- Make that is far more complex than we want to handle. So we only do such
-- processing on-demand when its needed.
local function makerule(makefn, targ, cwd)
  local rs = makeparse(makefn, cwd)
  local r = rs.normal[targ]
  if not r or #r == 0 then
    local fn = (#cwd > 0 and cwd..'/' or '')..targ
    if insrc(fn) then  -- Its a source file, so return the real name
      return insrc(fn)
    end

    -- Find the most applicable implicit rule for our purposes.
    local match,stem,found
    local errs = {}
    for ir in pairs(rs.implicit) do
      local p = unmagic(ir.name:gsub('%%', ':;!')):gsub(':;!', '(.+)')
      local s = targ:match(p)
      if #ir == 0 then assert(not ir.depstring:find '%g', ir.name..': '..ir.depstring)
      elseif s and (not match or #match.name <= #ir.name) then
        found = true
        -- Work through the postprocessed depstr and see if the deps are available
        local ok,ds = true,{}
        for d in ir.depstring:gsub('%%', s):gmatch '%g+' do
          if not d:find '^%.%./' then
            ok = ok and pcall(makerule, makefn, d, cwd)
            ds[#ds+1] = d
          end
        end
        if ok then
          assert(not match or #match.name ~= #ir.name, "Multiple implicits match!")
          match,stem = ir,s
        else errs[table.concat(ds, ',')] = true end
      end
    end
    if not match and found then
      local x = {}
      for t in pairs(errs) do x[#x+1] = '{'..t..'}' end
      error(cwd..'|'..makefn..': no '..table.concat(x, ' or '))
    end

    if match then
      -- Instance the implicit rule to get the unprocessed final recipe
      r = {name=targ, implicit=false, stem=stem}
      r.depstring = match.depstring:gsub('%%', stem)
      rs[targ] = r
      table.move(match, 1,#match, 1, r)
    end
    -- If it doesn't match, we'll just pretend its a pseudo-phony and move on.
    assert(r, cwd..':'..makefn..' '..targ)
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
  funcs['filter-out'] = function(vs, ws, str)
    ws,str = expand(ws,vs), expand(str,vs)
    assert(not ws:find '%%')
    local words = {}
    for w in ws:gmatch '%g+' do words[w] = '' end
    return (str:gsub('%g+', words))
  end
  function funcs.shell(vs, cmd)  -- By far the hairiest and most sensitive
    if cmd == 'cd $(srcdir);pwd' then return expand('$(srcdir)', vs)
    elseif cmd == 'pwd' then return './'..cwd
    else error('Unhandled shell: '..cmd) end
  end

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

local commands = {}

-- This is the actual recursive make call. We assume that the Makefiles are
-- written to actually work and aren't naturally recursive.
local makecache2 = {}
local realmake
local function make(f, t, cwd)
  f,t = canonicalize(f),canonicalize(t)
  local id = cwd..':'..f
  if makecache2[id] and makecache2[id][t] then return makecache2[id][t] end
  makecache2[id] = makecache2[id] or {}
  local o = realmake(f, t, cwd)
  makecache2[id][t] = o
  return o
end
function realmake(makefn, targ, cwd)
  if targ:find '^%.%./' then
    -- It belongs to another Makefile, assume Tup can figure it out.
    return canonicalize(cwd..'/'..targ)
  end

  local name, rule = makerule(makefn, targ, cwd)
  if not rule then return name end  -- Source file, don't do anything
  local realname = pclean((#cwd > 0 and cwd..'/' or '')..name)
  local printout,trules = false,{}
  local deps = {}
  for i,d in ipairs(rule.deps) do deps[i] = make(makefn, d, cwd) end

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
      local fn,targs = 'Makefile',{}
      for w in exc:match '^make%s+(.*)':gmatch '%g+' do
        if w:sub(1,1) == '-' then
          if w:sub(1,2) ~= '--' and w:find 'f' then
            fn = nil
          end
        elseif fn then table.insert(targs, w)
        else fn = w end
      end
      for _,t in ipairs(targs) do make(fn, t, cwd) end
      tr = '# make '..(fn and '' or '-f '..fn..' ')..table.concat(targs, ' ')
    elseif cmd:find '^@fail=;' then
      assert(cmd == AMrecurse, cmd)
      assert(not (targ:find '^distclean%-' or targ:find 'maintainer%-clean%-'))
      local target = targ:gsub('%-recursive$', '')
      for s in rule.expand('$(SUBDIRS)'):gmatch '%g+' do
        assert(s ~= '.')
        make('Makefile', target, canonicalize((#cwd > 0 and cwd..'/' or '')..s..'/'))
      end
      make('Makefile', target..'-am', cwd)
      tr = AM..'(recursive make call)'
    elseif cmd:find('^cd '..unmagic(tmpdir)..'/?%g* && $%(MAKE%)') then
      local d = cmd:match('^cd '..unmagic(tmpdir)..'/?(%g*)')
      assert(d, cmd)
      make('Makefile', 'all', canonicalize((#cwd > 0 and cwd..'/' or '')..d..'/'))
      tr = '# CMake recursion into '..d
    -- Simple compilation calls
    elseif cmd:find '$%(COMPILE%)' or cmd:find '$%(COMPILE.os%)' then
      local c = exc:match ';(.*)'  -- AM-style, after ;
      local first,ins,out = true,{},nil
      c = gosub(c, 'D:I:std:W:f:g,O:c,o:', {
        [false]=function(p) if first then first = false; return p end
          ins[#ins+1] = make(makefn, p, cwd)
        end,
        o=function(p) out = pclean((#cwd > 0 and cwd..'/' or '')..p) end,
        I=function(p)
          if p == '.' then return '-I'..canonicalize(cwd)
          elseif p == '..' then return '-I'..canonicalize(cwd..'/..')
          else return '-I'..pclean(p) end
        end,
      })
      assert(not c:find '%%o', c)
      tr = ': '..table.concat(ins, ' ')..' |> '..c..' -o %o %f |> '..out
    end
    if tr then
      if tr:sub(1,1) == ':' then print(tr); table.insert(commands, tr)
      elseif tr == '' then tr = '# Skipped: '..exc end
      trules[idx] = tr
    else printout = true end
  end
  if printout then
    dbg(cwd..'|'..makefn..' '..realname..': '..table.concat(deps, ' '))
    for i,c in ipairs(rule) do
      if trules[i] then dbg('  '..trules[i])
      else dbg('  $ '..rule.ex[i]); dbg('  % '..c) end
    end
  end
  return realname
end

make('Makefile', 'all', '')

print(": | "..exdeps.." |> ^ Wrote build.tup.gen^ printf '"
  ..table.concat(commands, '\\n'):gsub('\n', '\\n')
  .."' > %o |> build.tup.gen <"..group..">")
