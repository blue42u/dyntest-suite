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
local function asub(tag, attr, repl)
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

  for _,a in ipairs(tag.attr) do
    if ns[a.name] then
      a.value = r(a.value)
      tag.attr[a.name] = a.value
    end
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
  local outt = {}
  trans[t.name] = outt
  local tag = xtrav(header, t.xml)()
  table.sort(tag.kids, function(a,b) return aget(a, 'n') < aget(b, 'n') end)
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
collectgarbage()

-- 3. Walk through the CCT and update the keys, then sort based on those.
local function cctupdate(tag)
  for _,sub in ipairs(tag.kids) do
    if sub.name == 'M' then
      asub(sub, 'n', trans.metric)
    else
      assert(({PF=1,Pr=1,L=1,C=1,S=1,F=1,P=1,LM=1,A=1})[sub.name])
      asub(sub, 'n', trans.procedure)
      asub(sub, 'lm', trans.module)
      asub(sub, 'f', trans.file)
      asub(sub, 'i', 'cid')
      asub(sub, 's', 'csid')
      asub(sub, 'it', 'citid')
      cctupdate(sub)
    end
  end
  table.sort(tag.kids, function(a,b)
    if a.name ~= b.name then
      if a.name == 'M' then return true
      elseif b.name == 'M' then return false
      else return a.name < b.name end
    end
    for k in ('n,lm,f,l,a,v,it'):gmatch '[^,]+' do
      if aget(a,k) ~= aget(b,k) then return (aget(a,k) or '') < (aget(b,k) or '') end
    end
    return false
  end)
  collectgarbage('step', 100)
end
cctupdate(cct)

-- Spit it back out, as XML
local outxml = slax:xml(dom, {indent=2, sort=false})
local f = io.open(outfn, 'w')
f:write(outxml)
f:close()
