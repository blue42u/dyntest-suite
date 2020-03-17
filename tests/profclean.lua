-- luacheck: std lua53

local cwd, outfn = ...

package.path = cwd:gsub('/?$', '/')..'../external/slaxml/?.lua;'..package.path
local slax = require 'slaxdom'

-- Getter for the simpler attribute format
local function aget(tag, k)
  for _,a in ipairs(tag.attr) do
    if a.name == k then return a.value end
  end
end

-- Helper for walking around XML structures. Had it lying around.
local xtrav
do
  -- Matching function for tags. The entries in `where` are used to string.match
  -- the attributes ('^$' is added), and keys that start with '_' are used on
  -- the tag itself.
  local function xmatch(tag, where)
    if type(where) == 'string' then where = {_name=where} end
    for k,v in pairs(where) do
      local t = function(x) return aget(tag, x) end
      if k:match '^_' then k,t = k:match '^_(.*)', function(x) return tag[x] end end
      if not t(k) then return false end
      if type(v) == 'string' then
        if not string.match(t(k), '^'..v..'$') then return false end
      elseif type(v) == 'table' then
        local matchedone = false
        for _,v2 in ipairs(v) do
          if string.match(t(k), '^'..v2..'$') then matchedone = true end
        end
        if not matchedone then return false end
      end
    end
    return true
  end

  -- Find a tag among this tag's children that matchs `where`.
  local function xfind(tag, where, init)
    for i=init or 1, #tag.kids do
      local t = tag.kids[i]
      if xmatch(t, where) then return i, t end
    end
  end

  -- for-compatible wrapper for xfind
  local function xpairs_inside(s, init)
    return xfind(s.tag, s.where, init+1)
  end
  local function xpairs(tag, where)
    return xpairs_inside, {tag=tag, where=where}, 0
  end

  -- Super-for loop, exposed as an iterator using coroutines. It works.
  local function xnest(tag, where, ...)
    if where then
      for _,t in xpairs(tag, where) do xnest(t, ...) end
    else coroutine.yield(tag) end
  end
  function xtrav(...)
    local args = {...}
    return coroutine.wrap(function() xnest(table.unpack(args)) end)
  end
end

-- Handy functions for modifying the DOM
local function asub(tag, attr, repl, append)
  local r
  if type(repl) == 'string' then r = function() return repl end
  elseif type(repl) == 'table' then r = function(k) return repl[k] end
  elseif type(repl) == 'function' then r = repl end
  assert(r)

  local ns
  if type(attr) == 'string' then ns = {[attr]=true}
  elseif type(attr) == 'table' then
    if #attr == 0 then ns = attr else
      ns = {}
      for _,k in ipairs(attr) do ns[k] = true end
    end
  end
  assert(ns)

  local function handle(a)
    local old = a.value
    a.value = r(a.value)
    tag.attr[a.name] = a.value
    if a.value == nil then
      error('Nil replacement value for '..tostring(attr)..'='..tostring(old)..'!')
    end
  end

  local found = false
  for _,a in ipairs(tag.attr) do
    if ns[a.name] then
      found = true
      handle(a)
    end
  end

  if not found and append then
    assert(type(attr) == 'string')
    local a = {type='attribute', name=attr, value=r(nil)}
    table.insert(tag.attr, a)
    handle(a)
  end
end
local function xasub(...)
  local args = {...}
  local repl, attr = table.remove(args), table.remove(args)
  for tag in xtrav(table.unpack(args)) do
    asub(tag, attr, repl)
  end
end

-- Simple string-hash for outputing mostly unique but short names
local function minihash(s)
  assert(math.maxinteger == 0x7fffffffffffffff)
  local sponge = 0x10011001feeffeef
  for x in s:gmatch '.?.?.?' do
    local a,b,c = x:byte(1,#x)
    a,b,c = a or 0, b or 0, c or 1
    local v = (a<<16)|(b<<8)|(c)
    sponge = sponge ~ v
    sponge = (sponge << 7) | (sponge >> 57)
  end
  sponge = ((sponge) & 0xffff) ~ ((sponge >> 16) & 0xffff)
         ~ ((sponge >> 32) & 0xffff) ~ ((sponge >> 48) & 0xffff)
  return ('%04x'):format(sponge)
end

-- -1. Read in the the XML, and convert to the DOM.
local dom
do
  local xml = io.stdin:read 'a'
  xml = xml:gsub('<!DOCTYPE[^\n]-%[.-%]>', '')
  dom = slax:dom(xml, {stripWhitespace=true, simple=true})
end

-- 0. Nab some useful tags from the DOM for future reference.
local root = xtrav(dom, 'HPCToolkitExperiment', 'SecCallPathProfile')()
local header = xtrav(root, 'SecHeader')()
local cct = xtrav(root, 'SecCallPathProfileData')()

-- 1. Unify the metric, load module, file and procedure IDs, based on their
--    orders after sorting base on their names.
local trans = {}
for _,t in ipairs{
  {name='metric', xml='MetricTable', sub='Metric', code='Mx'},
  {name='module', xml='LoadModuleTable', sub='LoadModule', code='Lx'},
  {name='file', xml='FileTable', sub='File', code='Fx'},
  {name='procedure', xml='ProcedureTable', sub='Procedure', code='Px'},
} do
  local outt = {['']=t.code..'0000'}
  trans[t.name] = outt
  local tag = xtrav(header, t.xml)()
  table.sort(tag.kids, function(a,b)
    if aget(a, 'n') ~= aget(b, 'n') then return aget(a, 'n') < aget(b, 'n') end
    if t.name == 'procedure' then
      if aget(a, 'v') ~= aget(b, 'v') then return aget(a, 'v') < aget(b, 'v') end
    end
  end)
  for sub in xtrav(tag, t.sub) do
    assert(not outt[aget(sub, 'i')])
    outt[aget(sub, 'i')] = t.code..minihash(aget(sub, 'n'))
  end
  collectgarbage()
end

-- 2. Update the header components with the updated values.
for m in xtrav(header, 'MetricTable', 'Metric') do
  asub(m, {'i','partner'}, trans.metric)
  for mf in xtrav(m, 'MetricFormula') do
    asub(mf, 'frm', function(s) return s:gsub('$(%d+)', trans.metric) end)
  end
end
xasub(header, 'LoadModuleTable', 'LoadModule', 'i', trans.module)
xasub(header, 'FileTable', 'File', 'i', trans.file)
xasub(header, 'ProcedureTable', 'Procedure', 'i', trans.procedure)
xasub(header, 'TraceDBTable', 'TraceDB', 'i', 'id')
collectgarbage()

-- 3. Walk through the CCT and "hash" up the metrics in the subtree of each tag.
local taghash = {}
local function ccthash(tag)
  assert(math.maxinteger == 0x7fffffffffffffff)
  local hash = 0
  for _,sub in ipairs(tag.kids or {}) do
    if sub.name == 'M' then
      hash = hash + tonumber(aget(sub, 'v'))
    else
      hash = hash + ccthash(sub)
    end
  end
  taghash[tag] = hash
  return hash
end
ccthash(cct)

-- 4. Walk through the CCT and update the keys, then sort based on those.
local function cctupdate(tag)
  for _,sub in ipairs(tag.kids) do if sub.type == 'element' then
    if sub.name == 'M' then
      asub(sub, 'n', trans.metric)
    else
      assert(({PF=1,Pr=1,L=1,C=1,S=1,F=1,P=1,LM=1,A=1})[sub.name])
      asub(sub, 'n', trans.procedure)
      asub(sub, 'lm', trans.module)
      asub(sub, 'f', trans.file)
      asub(sub, 'i', 'Cx')
      asub(sub, 's', function(x) return trans.procedure[x] or 's' end)
      asub(sub, 'it', 'Cx')
      asub(sub, 'l', 'lineno')
      asub(sub, 'v', 'Vx', 'append')
      cctupdate(sub)
    end
  end end
  local function comp(a, b)
    local function lcomp(x,y)
      if x == y then return 0
      elseif x < y then return 1
      else return -1 end
    end
    if a.type ~= 'element' then
      if b.type ~= 'element' then return lcomp(tostring(a), tostring(b))
      else return 1 end
    elseif b.type ~= 'element' then return -1 end
    if a.name ~= b.name then
      if a.name == 'M' then return 1
      elseif b.name == 'M' then return -1
      else return lcomp(a.name, b.name) end
    end
    if taghash[a] ~= taghash[b] then return lcomp(taghash[a], taghash[b]) end
    for k in ('n,lm,f,l,a,v,it'):gmatch '[^,]+' do
      if aget(a,k) ~= aget(b,k) then return lcomp(aget(a,k) or '', aget(b,k) or '') end
    end
    if #a.kids ~= #b.kids then return lcomp(#a.kids, #b.kids) end
    for i,ak in ipairs(a.kids) do
      local bk = b.kids[i]
      local c = comp(ak, bk)
      if c ~= 0 then return c end
    end
    return 0
  end
  table.sort(tag.kids, function(x,y) return comp(x,y) == 1 end)
  -- table.insert(tag.attr, {name='taghash', value=tostring(taghash[tag])})
  collectgarbage('step', 100)
end
cctupdate(cct)

-- Spit it back out, as XML
local outxml = slax:xml(dom, {indent=2, sort=true})
local f = io.open(outfn, 'w')
f:write(outxml)
f:close()
