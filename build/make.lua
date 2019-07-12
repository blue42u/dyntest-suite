#!/usr/bin/env lua5.3
-- luacheck: std lua53

-- Somewhat automatic conversion from Makefiles to Tup rules.
-- Usage: ./make.lua <path/to/source> <path/to/install> <path/of/tmpdir> <extra deps>
local srcdir,instdir,tmpdir,exdeps,transforms,extdir = ...
srcdir = srcdir:gsub('/?$', '/')
instdir = instdir:gsub('/?$', '/')
tmpdir = tmpdir:gsub('/?$', '/')
extdir = extdir:gsub('/?$', '/')

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

-- Function for saving and copying data, by storing gzip in base64.
local function storefile(fn)
  local p = io.popen('gzip -n < '..fn..' | base64 -w0')
  local x = {}
  repeat
    local n = p:read(80000)
    x[#x+1] = n
  until not n
  pclose(p)
  return #x == 1 and x[1] or x
end
-- local function storefor(...)
--   local tmpf = tmpdir..'/ZZZluatmp'
--   local f = io.open(tmpf, 'w')
--   for _,l in ... do f:write(l) end
--   f:close()
--   return storefile(tmpf)
-- end
local function dumpin(dst)
  return "base64 -d | gzip -d > "..(dst or '%o')
end
local function dump(b64, ...) return "echo '"..b64.."' | "..dumpin(...) end
local function copy(fn, ...) return dump(storefile(fn), ...) end

-- A partially-correct implementation of getopt, for command line munging.
-- Opts is a table with ['flag'] = 'simple' | 'arg', or an optstring
local function gosub(s, opts, repl)
  if type(opts) == 'string' then
    local o = {}
    for f,a in opts:gmatch '([^,;:]+)([,;:])' do
      if a == ':' then o[f] = 'arg'
      elseif a == ';' then o[f] = 'argword'
      else o[f] = 'simple' end
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
  local firstnonopt = true
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
              assert(opts[f] ~= 'simple', "Can't handle multiple short options yet!")
              table.insert(bits, munch(f, a, '-'..f))
            elseif opts[w:sub(2,2)] ~= 'arg' then  -- That's all folks
              table.insert(bits, munch(f, nil, '-'..f))
            else  -- Argument in next word, mark for consumption
              cur,curfix = f,'-'..f..' '
            end
          else  -- Must be a long word. Break at the = if possible
            local f,e,a = w:sub(2):match '([^=]+)(=?)(.*)'
            assert(opts[f], "No option "..f..' for '..('%q'):format(s)..'!')
            if e == '=' then  -- There was an =, argument in this word.
              assert(opts[f] ~= 'simple', "Argument given to non-arg longer flag!")
              table.insert(bits, munch(f, a, '-'..f..'='))
            elseif opts[f] == 'simple' then  -- That's all folks
              table.insert(bits, munch(f, nil, '-'..f))
            else  -- Argument is in next word, mark for consumption
              cur,curfix = f,'-'..f..' '
            end
          end
        else  -- Non-option word. Format with repl[false]
          table.insert(bits, munch(firstnonopt, w, ''))
          firstnonopt = false
        end
      end
    end
  end
  return table.concat(bits, ' ')
end

local rinstdir = exec('realpath -m '..instdir):gsub('%s*$', '')
local exists,pclean,isinst,fullrpath
do
  local rspatt = '^'..unmagic(exec('realpath -m '..srcdir):gsub('/?%s*$', ''))..'(.*)'
  local ripatt = '^'..unmagic(rinstdir:gsub('/?%s*$', ''))..'(.*)'
  local rtpatt = '^'..unmagic(exec('realpath -m '..tmpdir):gsub('/?%s*$', ''))..'(.*)'
  local expatt = '^'..unmagic(canonicalize(extdir))
  local patts,afters = {},{}
  local rpath = {rinstdir..'/lib'}
  for p,v in transforms:gmatch '(%g+)=(%g+)' do
    patts['^'..unmagic(p)..'(.*)'] = v
    afters['^'..unmagic(canonicalize(v))] = true
    table.insert(rpath, (exec('realpath -m '..v..'/lib'):gsub('%s*$', '')))
  end
  fullrpath = table.concat(rpath, ':')
  local dircache = {}
  -- We often will need to check for files in the filesystem to know whether a
  -- file is a source file or not (implicit rules). This does the actual check.
  function exists(fn)
    fn = canonicalize(fn)
    local d,f = fn:match '^(.-)([^/]+)$'
    d = d:gsub('/?$', '/')  -- Ensure there's a / at the end
    if d:find(expatt) then return true end  -- Externals always exist
    -- Things that work with transforms always exist
    for p in pairs(afters) do if d:find(p) then return true end end
    if d:sub(1,1) ~= '/' and d:sub(1,3) ~= '../' then return false end
    if dircache[d] then return dircache[d][f] end

    local p = io.popen('find '..d..' -type f -maxdepth 1 2> /dev/null', 'r')
    local c = {}
    for l in p:lines() do c[l:match '[^/]+$'] = true end
    p:close()
    dircache[d] = c
    return c[f]
  end
  function isinst(p) return not not p:find(ripatt) end
  -- Paths sometimes will reference the source directories. This cleans a
  -- potental path to adjust references accordingly.
  -- Three paths are returned, one is the actual file w/ respect to the current
  -- location (build), the second is the location the file would be in if it was
  -- a build file, and the third is where it would be if it was a src file.
  function pclean(path, ref)
    ref = (ref and #ref > 0) and ref..'/' or ''
    local rev = ref:gsub('[^/]+', '..')
    if path:sub(1,1) == '/' then  -- Absolute path, try to find a good prefix
      local x = path:match(rspatt)
      if x then
        local z = canonicalize(srcdir..x)
        local y,w = x:gsub('^/',''):match '^(.-)([^/]*)$'
        return z,canonicalize(y..rev..w),z
      end
      x = path:match(ripatt)
      if x then x = canonicalize(instdir..x); return x,x,x end
      local res
      for p,d in pairs(patts) do if path:find(p) then
        x = path:match(p)
        if x then
          assert(not res, "Multiple patts match "..('%q'):format(path).."!")
          res = canonicalize(d..x)
        end
      end end
      if res then return res,res,res end
      x = path:match(rtpatt)
      if x then x = canonicalize(x:gsub('^/(.)', '%1')); return x,x,x end
      -- At this point all the prefixes have been tried. Must be a system thing.
      return path,path,path
    else  -- Relative path, use ref to sort it out
      local x = canonicalize(ref..path)
      return x,x,canonicalize(srcdir..ref..path)
    end
  end
end

local makevarpatt = '[%w_<>@.?%%^*+-]+'

-- We let make parse the Makefiles for us, and cache the outputs in a little
-- table to make things faster. Argument is the path to the Makefile.
local makecache = {}
local function makeparse(makefn, cwd)
  makefn = canonicalize(makefn)
  local id = cwd..':'..makefn
  if makecache[id] then return makecache[id] end

  local db = nil
  -- db = ' | tee /tmp/q_'..cwd:gsub('/','_')..'.'..makefn:gsub('/','_')
  local p = io.popen("cd "..tmpdir.."/"..cwd.." && "
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
    elseif state == 'defvar' then
      if l == 'endef' then state = 'vars' end
    elseif state == 'vars' then
      if l == '# Implicit Rules' then state = 'outsiderule' else
        if #l > 0 and l:sub(1,1) ~= '#' then
          if l:find '^define%s' then state = 'defvar' else
            local k,v = l:match('^('..makevarpatt..') :?= (.*)$')
            assert(k and v, l)
            c.vars[k] = v
          end
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

        if crule.implicit then
          if crule.name:find '_dis%.h$' then
            -- Hack for EU, put stuff in build
            local _
            _,crule.name = pclean(crule.name, cwd)
          end
          c.implicit[crule] = crule.name
        else
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

  makecache[id] = c
  return c
end

-- List of "hack" targets that AM doesn't handle very well.
local euhacks = {
  ['../libelf/libelf.so'] = true,
  ['../libdw/libdw.so'] = true,
  ['../lib/libeu.so'] = true,
  ['../lib/libeu.a'] = true,
  ['../../../libtool'] = true,
}

-- After a rule is parsed above, there is a lot of postprocessing that can be
-- done (variable expansion and implicit rule search), but there is a lot of
-- Make that is far more complex than we want to handle. So we only do such
-- processing on-demand when its needed.
local function makerule(makefn, targ, cwd)
  local rs = makeparse(makefn, cwd)
  local r = rs.normal[targ]
  if not r or #r == 0 then
    local fn,_,fnsrc = pclean(targ, cwd)
    if exists(fn) then return fn end
    if exists(fnsrc) then return fnsrc end
    if fn:find '^%.%.' then error('File '..fn..' does not exist!') end

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

    -- Hack for Elfutils, it doesn't really work in parallel. Tup will sort it.
    if euhacks[targ] then return fn end

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
    elseif cmd == 'pwd' then return './'..cwd
    elseif cmd == '$(AR) t ../libdwfl/libdwfl.a' then
      return [[dwfl_begin.o dwfl_end.o dwfl_error.o dwfl_version.o dwfl_module.o dwfl_report_elf.o relocate.o dwfl_module_build_id.o dwfl_module_report_build_id.o derelocate.o offline.o segment.o dwfl_module_info.o dwfl_getmodules.o dwfl_getdwarf.o dwfl_module_getdwarf.o dwfl_module_getelf.o dwfl_validate_address.o argp-std.o find-debuginfo.o dwfl_build_id_find_elf.o dwfl_build_id_find_debuginfo.o linux-kernel-modules.o linux-proc-maps.o dwfl_addrmodule.o dwfl_addrdwarf.o cu.o dwfl_module_nextcu.o dwfl_nextcu.o dwfl_cumodule.o dwfl_module_addrdie.o dwfl_addrdie.o lines.o dwfl_lineinfo.o dwfl_line_comp_dir.o dwfl_linemodule.o dwfl_linecu.o dwfl_dwarf_line.o dwfl_getsrclines.o dwfl_onesrcline.o dwfl_module_getsrc.o dwfl_getsrc.o dwfl_module_getsrc_file.o libdwfl_crc32.o libdwfl_crc32_file.o elf-from-memory.o dwfl_module_dwarf_cfi.o dwfl_module_eh_cfi.o dwfl_module_getsym.o dwfl_module_addrname.o dwfl_module_addrsym.o dwfl_module_return_value_location.o dwfl_module_register_names.o dwfl_segment_report_module.o link_map.o core-file.o open.o image-header.o dwfl_frame.o frame_unwind.o dwfl_frame_pc.o linux-pid-attach.o linux-core-attach.o dwfl_frame_regs.o gzip.o bzip2.o lzma.o]]  -- luacheck: no max line length
    elseif cmd == '$(AR) t ../libdwelf/libdwelf.a' then
      return [[dwelf_elf_gnu_debuglink.o dwelf_dwarf_gnu_debugaltlink.o dwelf_elf_gnu_build_id.o dwelf_scn_gnu_compressed_size.o dwelf_strtab.o dwelf_elf_begin.o]] -- luacheck: no max line length
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
local firstylwrap = true
local libtoollibs = {}

-- This is the actual recursive make call. We assume that the Makefiles are
-- written to actually work and aren't naturally recursive.
local makecache2 = {}
local realmake
local function make(f, t, cwd)
  f,t = canonicalize(f),canonicalize(t)
  local c1 = makecache2[cwd]
  if not c1 then c1 = {}; makecache2[cwd] = c1 end
  local c2 = c1[f]
  if not c2 then c2 = {}; c1[f] = c2 end
  if c2[t] then return c2[t] end
  local o = realmake(f, t, cwd)
  c2[t] = o
  return o
end
function realmake(makefn, targ, cwd)
  -- Targets that are actually handled via other methods are sorted up here.
  if targ == 'elfutils.pot-update' or targ == 'stamp-po'
    or targ:match '[^/]+$' == 'Makefile.in' then
    return targ
  end

  -- Hack to skip a target that fails miserably
  if pclean(targ, cwd) == 'src/tool/hpcrun/libhpcrun.o' then
    return pclean(targ, cwd)
  end

  local name, rule = makerule(makefn, targ, cwd)
  if not rule then return name end  -- Source file, don't do anything
  local realname = pclean(name, cwd)
  local printout,trules = false,{}
  local deps = {}
  for i,d in ipairs(rule.deps) do deps[i] = make(makefn, d, cwd) end

  for idx,cmd in ipairs(rule) do
    local exc = rule.ex[idx]
    local tr = nil
    local AM,CM = '# Automake configure ', '# CMake configure '
    if not cmd:find '%g' then tr = ' '
    elseif exc == ':' or exc:find '^:%s+>%s+' then tr = ' '
    elseif cmd:find '^@$%(MKDIR_P%)' then tr = AM..'(mkdir)'
    elseif cmd:find '^@$%(mkinstalldirs%)' then tr = AM..'(mkdirs)'
    elseif exc:find '!;@%g+@;!' then tr = ''
    elseif exc:find '^echo [^;]+$' then tr = ''
    -- Automake-generated rules and commands.
    elseif cmd:find '$%(ACLOCAL%)' then tr = AM..'(aclocal)'
    elseif cmd:find '$%(AUTOHEADER%)' then tr = AM..'(autoheader)'
    elseif cmd:find '$%(AUTOCONF%)' then tr = AM..'(autoconf)'
    elseif cmd:find '$%(SHELL%) %./config%.status' then tr = AM..'(config.status)'
    elseif cmd:find '$%(MAKE%) $%(AM_MAKEFLAGS%) am%-%-refresh' then tr = AM..'(refresh)'
    elseif exc:find '^test %-f config%.h' or exc:find '^if test ! %-f config%.h' then
      local c = exc:match '|| (.*)' or exc:match 'then ([^;]*)'
      if c:find '^%s*make%s' then  -- Copy config.h to the final product
        tr = ": |> ^o Wrote config.h^ "..copy(tmpdir..'/config.h').." |> config.h"
        exdeps = exdeps..' config.h'
      else tr = AM..'('..c..')' end
    elseif cmd == 'touch $@' then tr = ''
    elseif exc:find '^rm %-f' then tr = ''
    elseif cmd:find '$%(INSTALL' then
      local list = cmd:match "^@list='([^']+)'"
        or cmd:match "^@list1='';%s+list2='([^']+)'"
      local c
      for x in cmd:gmatch ';%s*($%(INSTALL[^|;]+)' do c = x end
      if not c then for x in cmd:gmatch '%s*($%(INSTALL[^|;]+)' do c = x end end
      assert(c, cmd)
      c = c:gsub('%s*$', ''):gsub('$$dir', '')
      local ins,outs,args = {},{},nil
      local g = 'bin'
      if list then
        assert(({files=true, list2=true, xfiles=true})[c:match '%s$$(%g+)'], c)
        c:gsub('$$x?files', '%%f'):gsub('$$list2', '%%f')
        local dir = pclean((rule.expand(c:match '%g+$'):gsub('"', '')))
        local fs = {}
        for w in rule.expand(list):gmatch '%g+' do
          if w:find '%.so%f[.\0]' then g = 'libs' end
          local d = w:match '(.-)[^/]+$'
          if not fs[d] then fs[d] = {} end
          table.insert(outs, dir..'/'..w)
          w = make(makefn, w, cwd)
          table.insert(fs[d], w)
          table.insert(ins, w)
        end
        args = {}
        for d,ws in pairs(fs) do
          table.insert(ws, dir..'/'..d)
          table.insert(args, table.concat(ws, ' '))
        end
      elseif cmd:find '^for m in $%(modules%)' then
        ins = ''
      else
        local s,d = c:match '%f[%g]([^$]%g+)%s+(%g+)'
        if s then
          if d:find '%.so%f[.\0]' then g = 'libs' end
          s,d = make(makefn, s, cwd),pclean(rule.expand(d))
          ins,outs,args = {s},{d},'%f %o'
        end
      end
      if not args then
        tr = '# '..cmd
      else
        local first = true
        c = gosub(rule.expand(c):match '/install.*', 'c,m:', {
          [true]='LD_PRELOAD= install',
          [false]=function() if first then first = false; return ':!;' end end,
        })
        local post = ' && touch %o'
        if type(args) == 'string' then
          c = c:gsub(':!;', (args:gsub('%%', '%%%%')))
        else
          local cs = {}
          for i,as in ipairs(args) do
            cs[i] = c:gsub(':!;', (as:gsub('%%', '%%%%')))
          end
          c = table.concat(cs, ' && ')
        end
        if #outs > 0 then
          tr = ': '..table.concat(ins, ' ')..' |> ^ Installed %o^ '..c..post..' |> '
            ..table.concat(outs, ' ')..' <'..g..'>'
        else tr = '# Skipping empty installation' end
      end
    elseif cmd:find '^$%(mkinstalldirs%)' then tr = AM..'(mkdir)'
    -- CMake-generated rules and commands.
    elseif cmd:find '^$%(CMAKE_COMMAND%) %-S' then tr = CM..'(check build sys)'
    elseif cmd:find '^$%(CMAKE_COMMAND%) %-E cmake_progress' then tr = CM..'(progress start)'
    elseif cmd:find '^@$%(CMAKE_COMMAND%) %-E cmake_echo' then tr = CM..'(progress bar)'
    elseif cmd:find '$%(CMAKE_COMMAND%) %-E cmake_depends' then tr = CM..'(dependency scan)'
    elseif cmd:find '^@$%(CMAKE_COMMAND%) %-E touch_nocreate' then tr = CM..'(touch)'
    elseif cmd:find '^$%(CMAKE_COMMAND%) %-P %g+cmake_clean_target%.cmake' then tr = CM..'(clean)'
    elseif cmd:find '%s%-P%s+cmake_install%.cmake' then
      local cmds = {}
      local parsecache,dedup = {},{}
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
                a = a:gsub('"', ''):gsub('${CMAKE_INSTALL_PREFIX}', instdir)
                outdir = pclean(a)
              elseif ty == false then ty = a
              elseif renm == false then renm = a:gsub('"', '')
              elseif a == 'DESTINATION' then outdir = false
              elseif a == 'TYPE' then ty = false
              elseif a == 'RENAME' then renm = false
              elseif not skip[a] then
                assert(a:find '"', a)
                a = a:gsub('"', ''):gsub('${CMAKE_INSTALL_PREFIX}', instdir)
                a = pclean(a)
                if not a:find '%.cmake$' and not a:find '%.txt$'
                  and not a:find '%.pdf$' then
                  table.insert(ins, a)
                end
              end
            end
            if #ins > 0 and ty ~= 'DIRECTORY' then
              local tyargs = {
                SHARED_LIBRARY='', EXECUTABLE='', FILE=' -m 644',
                STATIC_LIBRARY=' -m 644',
              }
              assert(tyargs[ty], 'No install args for '..ty)
              local install = '^o Installed %o^ LD_PRELOAD= install '
              local inspost = ' && touch %o'
              if renm then
                assert(#ins == 1)
                if not dedup[ins[1]] then
                  local g = ty:find 'LIBRARY' and 'libs' or 'bin'
                  table.insert(cmds, ': '..ins[1]..' |> '..install
                    ..'%f %o'..inspost..' |> '..outdir..'/'..renm..' <'..g..'>')
                  dedup[ins[1]] = true
                end
              else
                local outs,ex = {},{}
                local doit = false
                for i,v in ipairs(ins) do
                  if not dedup[v] then
                    if ty == 'SHARED_LIBRARY' and not ex.so then
                      ex[#ex+1], ex.so = '<_so>', true
                    end
                    outs[i] = canonicalize(outdir..'/'..v:match '[^/]+$')
                    dedup[v] = true
                    doit = true
                  else ins[i],outs[i] = '','' end
                end
                if doit then
                  ex = #ex > 0 and ' | '..table.concat(ex, ' ') or ''
                  local g = ty:find 'LIBRARY' and 'libs' or 'bin'
                  table.insert(cmds, ': '..table.concat(ins, ' ')..ex..' |> '
                    ..install..'%f '..outdir..inspost..' |> '..table.concat(outs, ' ')
                    ..' <'..g..'>')
                end
              end
            end
          end
        end
      end
      parse(tmpdir..'cmake_install.cmake')
      tr = table.concat(cmds, '\n')
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
        make('Makefile', target, pclean(s, cwd))
      end
      make('Makefile', target..'-am', cwd)
      tr = AM..'(recursive make call)'
    elseif cmd:find('^cd '..unmagic(tmpdir)..'/?%g* && $%(MAKE%)') then
      local d = cmd:match('^cd '..unmagic(tmpdir)..'/?(%g*)')
      assert(d, cmd)
      make('Makefile', 'all', pclean(d, cwd))
      tr = '# CMake recursion into '..d
    -- Simple compilation calls
    elseif cmd:find '$%(COMPILE%)' or cmd:find '$%(COMPILE.os%)'
      or cmd:find '$%([^)]*LINK%)' or cmd:find '$%(CC%)' or cmd:find '$%(CXX%)'
      or cmd:find '$%(C_FLAGS%)' or cmd:find '$%(CXX_FLAGS%)'
      or cmd:find '$%(CCAS%)' then
      local amstyle,delibtoolize = false,false
      local c,linkargs,compilation
      if cmd:find '$%(LIBTOOL%)' or exc:find '/libtool' then
        delibtoolize,c = exc:match '^.-%-%-mode=(%g+)%s+(.*)'
        assert(delibtoolize and c, exc)
        assert(delibtoolize == 'compile' or delibtoolize == 'link')
        amstyle = true
        linkargs = {}
      else
        c = exc:match ';%s*(.*)'
        if c then amstyle = true else c = exc:match '&&%s*(.*)' or exc end
      end
      local cd = cmd:match '^%s*cd%s+(%g+)'
      cd = cd and pclean(cd) or cwd
      -- Glitchy thing with one of the commands. The system will figure it out.
      c = c:gsub(
        unmagic(rule.expand "`test -f ':;!' || echo '$(srcdir)/'`")
          :gsub(':;!', "[^']+"),
        '')
      local ins,out = {},nil
      local mydeps = ''
      local cpre = cd:gsub('[^/]+', '..'):gsub('/?$', '/'):gsub('^/$', '')
      local function li(p)
        if p:sub(1,1) == '/' then return cpre..pclean(p)
        else return pclean(p) end
      end
      c = gosub(c, 'D:I:std:W;f:g,O:c,o:shared,l:w,L:rpath:', {
        [false]=function(p)
          if not out then
            out = pclean(p:gsub('%.%g+$', '.o'), cd)
          end
          p = make(makefn, p, cwd)
          if not exists(p) and p:sub(1,1) ~= '/' then table.insert(ins, p) end
          return cpre..p
        end,
        o=function(p)
          out = pclean(p, cd)
          return '-o '..cpre..out
        end,
        I=function(a, pre) return pre..li(a) end,
        L=function(a, pre)
          a = li(a)
          if linkargs then table.insert(linkargs, pre..a) end
          return pre..a --..' -Wl,--rpath,`realpath '..a..'`'
        end,
        l=function(a,pre)
          a = pre..a
          if linkargs then table.insert(linkargs, a) end
          return a
        end,
        rpath=function(p)
          assert(delibtoolize == 'link')
          p = '-Wl,--rpath,`realpath '..p:gsub('[^:]+', pclean)..'`'
          table.insert(linkargs, p)
          return p
        end,
        W=function(a)
          if not a then return '-W' end
          local vs = a:match '^l,%-%-version%-script,(.*)'
          if vs then
            local f,e = vs:match '([^,]+)(.*)'
            f = pclean(f)
            if not f:find '^%.%./' then mydeps = mydeps..' '..f end
            return '-Wl,--version-script,'..cpre..f..e
          end
          vs = a:match '^l,%-%-rpath,(.*)'
          if vs then
            a = 'l,--rpath,'..vs:gsub('[^:]+', function(x)
              return '`realpath '..pclean(x)..'`'
            end)
            if linkargs then table.insert(linkargs, '-W'..a) end
          end
          return '-W'..a
        end,
        c=function() compilation = true; return '-c' end,
      })
      assert(not c:find '%%o', c)
      -- Hacks for handling oddities in Elfutils
      if amstyle then
        c = c..' -DHAVE_CONFIG_H '
        local x = out:match '%s*libcpu/(%g-)_disasm%.o%s*'
        if x and x ~= 'libcpu_bpf_a-bpf' then
          mydeps = mydeps..' '..make(makefn, x..'.mnemonics', cwd)
            ..' '..make(makefn, x..'_dis.h', cwd)
        end
        if out == 'src/objdump' then
          mydeps = mydeps..' libdw/libdw.so.1'
        end
      end
      -- Hacks to make sure all the RUNPATHs are sorted
      if not compilation then
        c = c..' -Wl,--rpath,'..fullrpath
        if not out:find '%.so' then mydeps = mydeps..' <libs>' end
      end
      local cdcd = #cd > 0 and 'cd '..cd..' && ' or ''
      if delibtoolize then
        -- Tack on the arguments needed for the linked .la files.
        for _,i in ipairs(ins) do
          if i:find '%.la$' or i:find '%.lo$' then
            assert(libtoollibs[i], i)
            table.insert(linkargs, libtoollibs[i])
          end
        end
        if out:find '%.la$' or out:find '%.lo' then
          assert(not libtoollibs[out])
          libtoollibs[out] = table.concat(linkargs, ' ')
        end
        if out:find '%.la$' then
          -- Libtool uses commands that look like normal linking for making .la.
          -- While clever and convenient, we just make it a normal ar command.
          cdcd,c = '','ar scr %o %f'
        else c = c .. ' ' .. table.concat(linkargs, ' ') end
      end
      tr = ': '..table.concat(ins, ' ')..' |^ <_gen> '..mydeps..'|> ^o '
        ..(compilation and 'cc' or 'ld')..' -o %o ...^ '..cdcd..c..' |> '..out
    -- Simple archiving (AR) calls
    elseif cmd:find '$%(RANLIB%)' then tr = ''  -- Skip ranlib
    elseif cmd:find '$%([%w_]+AR%)' then
      local ins,out = {},pclean(rule.name, cwd)
      for i,d in ipairs(rule.deps) do
        ins[i] = pclean(d, cwd)
      end
      tr = ': '..table.concat(ins, ' ')..' |> ^o ar %o ...^ ar scr %o %f |> '..out
    -- Linking for CMake, a combo of the above two sections
    elseif cmd:find '$%(CMAKE_COMMAND%)%s+%-E%s+cmake_link_script' then
      local cd = cmd:match '^%s*cd%s+(%g+)'
      cd = cd and pclean(cd) or cwd
      local l = assert(cmd:match '%-E%s+cmake_link_script%s+(%g+)')
      local f = assert(io.open(tmpdir..pclean(l, cd)))
      local cmds = {}
      for c in f:lines 'l' do
        if c:find '^%g+%s+qc' then  -- ar command actually
          local ar = c:match '^%g+'
          local ins,out = {},nil
          for w in c:match '%sqc%s+(.+)':gmatch '%g+' do
            w = pclean(w, cd)
            if not out then out = w else table.insert(ins, w) end
          end
          c = ': '..table.concat(ins, ' ')..' |> ^o ar %o ...^ '..ar..' scr %o %f |> '..out
        elseif c:find '^%g+%s+%g+$' then  -- Probably a ranlib, we skip it.
          c = nil
        else  -- Assume its a cc-style command
          local ins,out = {},nil
          local function li(p, pre)
            if p == '.' then return pre..pclean(p, cd)
            elseif p == '..' then return pre..pclean(p, cd)
            else return pre..pclean(p, cd) end
          end
          c = gosub(c, 'D:f:W;O:g,shared,o:l:std:L:I:', {
            [false]=function(p)
              p = pclean(p, cd)
              if not exists(p) and p:sub(1,1) ~= '/' then table.insert(ins, p) end
              return p
            end,
            o=function(p) out = pclean(p, cd); return '-o %o' end,
            W=function(x)
              if not x then return '-W' end
              local rp = x:match 'l,%-rpath,(.*)'
              if rp then
                return '-Wl,-rpath,'..rp:gsub('[^:]+', function(z)
                  return '`realpath '..pclean(z)..'`'
                end)
              end
              return '-W'..x
            end,
            l=function(x)
              assert(not x:find '/', x)
              return '-l'..x
            end,
            L=li, I=li,
          })
          -- Hack to make sure all the RUNPATHs are sorted
          c = ': '..table.concat(ins, ' ')..' |^ <_gen> |> ^o ld -o %o ...^ '
            ..c..' -Wl,--rpath,'..fullrpath..' |> '..out..' <_so>'
        end
        cmds[#cmds+1] = c
      end
      f:close()

      assert(#cmds == 1, "Too many commands!")
      tr = cmds[1]
    -- Generation expressions: gawk, sed, m4 and ./i386_gendis
    elseif exc:find '^gawk' then
      local ins,out = {},nil
      local c = gosub(exc, 'f,', {
        [false]=function(p)
          if p == '>' then out = false; return '>'
          elseif out == false then
            if p:find '/known%-dwarf%.h%.new$' then p = 'known-dwarf.h.new' end
            out = pclean(p, cwd)
            return '%o'
          else
            ins[#ins+1] = make(makefn, p, cwd)
            if #ins == 1 then return '%f' end
          end
        end,
      })
      tr = ': '..table.concat(ins, ' ')..' |> ^o gawk > %o ...^ '..c..' |> '..out..' <_gen>'
    elseif exc:find ';m4%s' then
      local ins,out = {},nil
      local c = gosub(exc:match ';(.*)', 'D:', {
        [false]=function(p)
          if p == '>' then out = false; return '>'
          elseif out == false then out = pclean(p, cwd); return '%o'
          else
            ins[#ins+1] = make(makefn, p, cwd)
            if #ins == 1 then return '%f' end
          end
        end,
      })
      tr = ': '..table.concat(ins, ' ')..' |> ^o m4 > %o ...^ '..c..' |> '..out..' <_gen>'
    elseif exc:find ';%s*sed%s' or exc:find '^sed%s' then
      local rcmd = exc:gsub('^%s*echo[^;]+;', '')
      local pre,sed = rcmd:match '(.-;)%s*(sed.*)'
      if not pre then pre,sed = '',rcmd end
      local ins,out = {},nil
      local c = pre:gsub(rinstdir, '')..gosub(sed, 'u,e:', {
        [false]=function(p)
          if p == '|' or p == 'sort' or p:sub(1,1) == "'" then
            return p:gsub('%%', '%%%%')
          elseif p == '>' then out = false; return '>'
          elseif out == false then out = pclean(p, cwd); return '%o'
          else
            ins[#ins+1] = make(makefn, p, cwd)
            if #ins == 1 then return '%f' end
          end
        end,
        e=function(x) return '-e '..x:gsub('%%', '%%%%') end,
      })
      tr = ': '..table.concat(ins, ' ')..' |> ^o sed > %o ...^ '..c..' |> '..out..' <_gen>'
    elseif exc:find ';%./i386_gendis%s' then  -- Hardcoded from EU
      local ins,out,gd = {},nil,nil
      local c = gosub(exc:match ';(.*)', '', {
        [true]=function(p) gd = make(makefn, p, cwd); return './'..gd end,
        [false]=function(p)
          if p == '>' then out = false; return '>'
          elseif out == false then out = pclean(p, cwd); return '%o'
          else
            ins[#ins+1] = make(makefn, p, cwd)
            if #ins == 1 then return '%f' end
          end
        end,
      })
      tr = ': '..table.concat(ins, ' ')..'| '..gd..' |> ^o ./gendis > %o ...^ '..c..' |> '..out
    -- Symlink creation calls
    elseif exc:find '^ln%s' then
      local args = {}
      for w in exc:gmatch '%f[%g][^-]%g+' do args[#args+1] = w end
      assert(#args == 3, '{'..table.concat(args, ', ')..'}')
      if isinst(args[3]) then
        local g = args[3]:find '%.so%f[.\0]' and 'libs' or 'bin'
        tr = ': |> LD_PRELOAD= ln -sf '..args[2]..' %o && touch %o |> '..pclean(args[3], cwd)..' <'..g..'>'
      else
        local src,dst = pclean(args[2],cwd), pclean(args[3],cwd)
        tr = ': '..src..' |> ln -sf %f %o |> '..dst
      end
    elseif cmd:find '$%(CMAKE_COMMAND%)%s+%-E%s+cmake_symlink_library' then
      local cd = cmd:match '^%s*cd%s+(%g+)'
      cd = cd and pclean(cd) or cwd
      local src,dsts = nil,{}
      for w in cmd:match 'cmake_symlink_library%s+(.*)':gmatch '%g+' do
        if not src then src = w else table.insert(dsts, w) end
      end
      local cmds = {}
      for i,v in ipairs(dsts) do
        dsts[i] = pclean(v, cd)
        cmds[i] = 'LD_PRELOAD= ln -sf '..src..' '..dsts[i]
      end
      tr = ': |> '..table.concat(cmds, ' && ')..' && touch %o |> '..table.concat(dsts, ' ')..' <bin>'
    -- Elfutils does a check that TEXTREL doesn't appear in the output .so.
    elseif cmd == '@$(textrel_check)' then
      if not trules[idx-1] then
        tr = '# TEXTREL check skipped, unable to fold.'
      else
        assert(trules[idx-1]:find '|>.*|>%s*%g+%.so', "textrel_check not after .so output!")
        local o = trules[idx-1]:match '%f[%g]%-o%s+([^%s%%]+)'
        local c = '&& ! (readelf -d '..o..' | grep -Fq TEXTREL '
          ..'&& echo "WARNING: TEXTREL found in %%o!")'
        trules[idx-1] = trules[idx-1]:gsub('|>(.*)|>', '|>%1 '..c..' |>')
        tr = '# TEXTREL check folded into previous command'
      end
    elseif exc:find '^chmod%s+%+x' then
      assert(trules[idx-1], "chmod can't fold behind!")
      local c = '&& chmod +x %%o'
      trules[idx-1] = trules[idx-1]:gsub('|>(.*)|>', '|>%1 '..c..' |>')
      tr = '# chmod +x folded into previous command'
    -- Elfutils does a gawk-then-move trick for some reason. We do it this way.
    elseif exc:find '^mv%s' then
      local args = {}
      for w in exc:gmatch '%f[%g][^-]%g+' do args[#args+1] = w end
      assert(#args == 3, '{'..table.concat(args, ', ')..'}')
      if args[2]:find '/known%-dwarf%.h%.new$' then args[2] = 'known-dwarf.h.new' end
      if args[3]:find '/known%-dwarf%.h$' then args[3] = 'known-dwarf.h' end
      local src,dst = pclean(args[2],cwd),pclean(args[3],cwd)
      src,dst = unmagic(src), dst:gsub('%%', '%%%%')
      for k,v in pairs(trules) do trules[k] = v:gsub(src, dst) end
      exdeps = exdeps:gsub(src, dst)
      tr = '# mv folded into previous commands'
    -- Elfutils also generates .map files at times. Handle it here.
    elseif cmd == "$(AM_V_at)echo 'ELFUTILS_$(PACKAGE_VERSION) { global: $*_init; local: *; };' > $(@:.so=.map)" then
      local ver = rule.expand '$(PACKAGE_VERSION)'
      local out = pclean(rule.expand '$(@:.so=.map)')
      tr = ": |> ^o Wrote %o^ echo 'ELFUTILS_"..ver.." { global: "
        ..rule.stem.."_init; local: *; };' > %o |> "..out
    -- HPCToolkit generates man pages from latex files. Why, I do not know.
    elseif cmd:find '^$%(MYLATEX2MAN%)' then
      local fs = {}
      local c = gosub(exc, 't:H,', {
        [true]=function(x) return pclean(x, cwd) end,
        t=function(x) return '-t '..pclean(x, cwd) end,
        [false]=function(p)
          if #fs == 0 then table.insert(fs, make(makefn, p, cwd)); return '%f'
          elseif #fs == 1 then table.insert(fs, (pclean(p, cwd))); return '%o'
          else error(exc) end
        end,
      })
      tr = ': '..fs[1]..' |> ^o Latex2Man %o^ '..c..' |> '..fs[2]
    -- YLWRAP-style commands are hardcoded. It would be too complex otherwise.
    elseif cmd:find '$%(YLWRAP%)' then
      if firstylwrap then
        firstylwrap = false
        print(": |> ^o Wrote ylwrap^ "..copy(srcdir..'/config/ylwrap')
          .." && chmod u+x %o |> ylwrap")
      end
      local c = cmd:match '$%(YLWRAP%)%s+(.*)'
      assert(c)
      if c == '$< $(LEX_OUTPUT_ROOT).c $@ -- $(LEXCOMPILE)' then
        local top = #cwd > 0 and cwd:gsub('[^/]+', '..')..'/' or ''
        local ylw = 'LD_PRELOAD= '..top..'ylwrap'
        local cd = #cwd > 0 and 'cd '..cwd..' && ' or ''
        tr = (': %s | ylwrap |> ^o ylwrap > %%o^ %s%s %s %s.c %s -- %s && touch %s |> %s <_gen>'):format(
          deps[1], cd, ylw, top..deps[1],
          rule.expand '$(LEX_OUTPUT_ROOT)', targ,
          rule.expand '$(LEXCOMPILE)', targ, realname)
      elseif c == '$< y.tab.c $@ y.tab.h `echo $@ | $(am__yacc_c2h)` y.output $*.output -- $(YACCCOMPILE)' then
        local top = #cwd > 0 and cwd:gsub('[^/]+', '..')..'/' or ''
        local ylw = 'LD_PRELOAD= '..top..'ylwrap'
        local cd = #cwd > 0 and 'cd '..cwd..' && ' or ''
        local function c2h(x)
          return x:gsub('cc$','hh'):gsub('cpp$','hpp'):gsub('c%+%+$','h++'):gsub('c$','h')
        end
        tr = (': %s | ylwrap |> ^o ylwrap > %%o^ %s%s %s y.tab.c %s y.tab.h'
          ..' %s y.output %s.output -- %s && touch %s %s |> %s %s <_gen>'):format(
            deps[1], cd, ylw, top..deps[1],
            targ, c2h(targ), assert(rule.stem),
            rule.expand('$(YACCCOMPILE)'),
            targ, c2h(targ),
            realname, c2h(realname))
      else error('Unhandled YLWRAP: '..cmd) end
    end
    if tr then
      if tr == '' then tr = '# Skipped: '..exc end
      trules[idx] = tr
    else printout = true end
  end
  for _,v in pairs(trules) do
    if v and v:sub(1,1) == ':' then table.insert(commands, v) end
  end
  if printout then
    dbg()
    dbg(cwd..'|'..makefn..' '..realname..': '..table.concat(deps, ' '))
    for i,c in ipairs(rule) do
      if trules[i] then
        if trules[i]:find '%g' then dbg('  '..trules[i]) end
      else dbg('  $ '..rule.ex[i]); dbg('  % '..c) end
    end
  end
  return realname
end

-- Copy over files that are built by the build systems and needed for cc etc.
for _,f in ipairs{
  'config/libelf.pc', 'config/libdw.pc',  -- Elfutils pkg-config stuff
  'version.h', -- Automake version header
  'libtool!',  -- Libtool script
  'common/h/dyninstversion.h',  -- Dyninst version header
  -- HPCToolkit boot scripts
  'src/tool/hpcstruct/hpcstruct', 'src/tool/hpcstruct/dotgraph',
  'src/tool/hpcprof/hpcprof', 'src/tool/hpcproftt/hpcproftt',
  'src/tool/hpcprof-flat/hpcprof-flat', 'src/tool/hpcprof-mpi/hpcprof-mpi',
  'src/tool/hpcfnbounds/hpcfnbounds', 'src/tool/hpcrun/scripts/hpcrun',
  'src/tool/hpcrun/scripts/hpclink', 'src/tool/hpcrun/scripts/hpcsummary',
  'src/include/hpctoolkit-config.h', -- HPCToolkit configuration header
} do
  local p = ''
  if f:find '!$' then
    f = f:gsub('!$', '')
    p = ' && chmod +x %o'
  end
  if exists(tmpdir..f) then
    local data = storefile(tmpdir..f)
    if type(data) == 'string' then
      table.insert(commands, ': |> ^o Wrote %o^ '..dump(data)..p..' |> '
        ..f..' <_gen>')
    else
      for i,b in ipairs(data) do
        local ff = f..i
        io.stdout:write(": |> ^o Wrote %o^ echo '",b,"' > %o |> "..ff..'\n')
        data[i] = ff
      end
      io.stdout:write(': '..table.concat(data, ' ')..' |> ^o Concatinated %o^ '
        ..'cat %f | '..dumpin()..' |> '..f..'\n')
    end
  end
end

make('Makefile', 'all', '')
make('Makefile', 'install', '')

local x = exdeps:find '%g' and '| '..exdeps..' ' or '|'
for i,c in ipairs(commands) do
  io.stdout:write(c:gsub('|^', x),'\n')
  commands[i] = c..'\n'
end
