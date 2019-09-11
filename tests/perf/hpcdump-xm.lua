-- Parse an experiment.mt and experiment.xml file, and extract out the
-- bits that we care about.
-- luacheck: std lua53

-- Make sure we can access SLAXML from here
package.path = '../../external/slaxml/?.lua;'..package.path

-- Helper for walking around XML structures. Had it lying around.
local xtrav
do
  -- Matching function for tags. The entries in `where` are used to string.match
  -- the attributes ('^$' is added), and keys that start with '_' are used on
  -- the tag itself.
  local function xmatch(tag, where)
    for k,v in pairs(where) do
      local t = tag.attr
      if k:match '^_' then k,t = k:match '^_(.*)', tag end
      if not t[k] then return false end
      if type(v) == 'string' then
        if not string.match(t[k], '^'..v..'$') then return false end
      elseif type(v) == 'table' then
        local matchedone = false
        for _,v2 in ipairs(v) do
          if string.match(t[k], '^'..v2..'$') then matchedone = true end
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

-- First we generate stacktraces for all the relevant bits
local function trace(dbpath)
  local traces = {}
  -- Parse the XML and generate an (overly large) DOM table from it
  local f = assert(io.open(dbpath))
  local xml = f:read '*a'
  xml = xml:match '<!.-]>(.+)'
  local dom = require 'slaxdom':dom(xml)
  f:close()

  -- We actually only care about the SecCallPathProfile node, that's our root
  local rt = assert(xtrav(dom.root, {_name='SecCallPathProfile'})())
  local hd = assert(xtrav(rt, {_name='SecHeader'})())
  local pd = assert(xtrav(rt, {_name='SecCallPathProfileData'})())

  -- First order of business, find and condense the ProcedureTable
  local procs = {}
  for t in xtrav(hd, {_name='ProcedureTable'}, {_name='Procedure'}) do
    procs[t.attr.i] = t.attr.n
  end

  -- Next go through the traces and record them as small tables, recursively.
  local tr = {}
  local function process(t)
    -- Add this tag's place to the common trace
    if t.attr.n then tr[#tr+1] = assert(procs[t.attr.n]) end

    -- Make a copy and register in the traces
    if t.attr.it then traces[tonumber(t.attr.it)] = table.move(tr, 1,#tr, 1, {}) end

    -- Recurse for every useful next frame
    for tt in xtrav(t, {_name={'PF','Pr','L','C','S'}}) do process(tt) end

    -- Remove the trace added by this call
    if t.attr.n then tr[#tr] = nil end
  end
  for t in xtrav(pd, {_name='PF'}) do process(t) end
  return traces
end

-- Next we process the timepoint data.
local function timepoint(dbpath, traces)
  local tps = {}
  local f = io.open(dbpath, 'r')
  local function read(fmt, ...)
    if type(fmt) == 'string' then
      local sz = fmt:packsize()
      local d = f:read(sz)
      assert(d and #d == sz, 'Ran into EOF!')
      return ('>'..fmt):unpack(d)
    else return f:read(fmt, ...) end
  end

  local idx, offsets = 1, {}
  offsets[1] = 0
  offsets[#offsets+1] = f:seek 'end'

  do
    -- Figure out the properties of this file
    local offset = offsets[idx]
    local num_datums = (offsets[idx+1] - offset - 32) / (8+4)
    assert(math.floor(num_datums) == num_datums, num_datums)
    num_datums = math.floor(num_datums)

    -- Skip to that location, and ensure the header is there
    f:seek('set', offset)
    do
      local header,flags = read 'c24 i8'  -- 24-byte string + 8-byte integer
      assert(header == 'HPCRUN-trace______01.01b')
      assert(flags == 0)
    end

    -- Read in all the timepoints
    for _=1,num_datums do
      local time,id = read 'i8 i4'  -- 8-byte integer + 4-byte integer
      if traces[id] then
        table.insert(tps, {time=time / 1000000, trace=traces[id]})
      end
    end
  end

  f:close()
  return tps
end

local dbpath = ...
local traces = trace(dbpath:match '^(.*/)[^/]*$'..'experiment.xml')
local tps = timepoint(dbpath, traces)

for _,t in ipairs(tps) do
  print(t.time)
  for _,c in ipairs(t.trace) do
    print('  '..c)
  end
end
