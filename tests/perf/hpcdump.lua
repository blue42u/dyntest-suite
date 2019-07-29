-- Parse an experiment.mt and experiment.xml file, and extract out the
-- bits that we care about.
-- luacheck: std lua53

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

local dbpath = ...
package.path = '../../external/slaxml/?.lua;'..package.path

-- First we generate stacktraces for all the relevant bits
local traces = {}
do
  -- Parse the XML and generate an (overly large) DOM table from it
  local f = assert(io.open(dbpath..'/experiment.xml'))
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
  local trace = {}
  local function process(t)
    -- Add this tag's place to the common trace
    if t.attr.n then trace[#trace+1] = assert(procs[t.attr.n]) end

    -- Make a copy and register in the traces
    if t.attr.it then traces[tonumber(t.attr.it)] = table.move(trace, 1,#trace, 1, {}) end

    -- Recurse for every useful next frame
    for tt in xtrav(t, {_name={'PF','Pr','L','C','S'}}) do process(tt) end

    -- Remove the trace added by this call
    if t.attr.n then trace[#trace] = nil end
  end
  for t in xtrav(pd, {_name='PF'}) do process(t) end
end

-- Next we process the timepoint data.
local tps = {}
do
  local f = io.open(dbpath..'/experiment.mt', 'r')
  local function read(fmt, ...)
    if type(fmt) == 'string' then
      local sz = fmt:packsize()
      local d = f:read(sz)
      assert(d and #d == sz, 'Ran into EOF!')
      return ('>'..fmt):unpack(d)
    else return f:read(fmt, ...) end
  end

  local idx, offsets = 1, {}
  if f then
    -- First read in the megatrace header: 8 bytes.
    local _, num_files = read 'i4 i4'  -- 4-byte int + 4-byte int

    -- For each of the contained files, read in its properties and offset.
    for i=1,num_files do
      local pid,tid,offset = read 'i4 i4 i8'  -- 4-byte int + 4-byte int + 8-byte int
      offsets[i] = offset
      if pid == 0 and tid == 0 then idx = i end
    end
  else
    -- Sometimes there is no megatrace. Try to use the original hpctrace.
    f = assert(io.popen('ls -1 '..dbpath..'/*-000000-000-*.hpctrace'))
    local fn = assert(f:read '*l')
    assert(f:close())
    f = assert(io.open(fn, 'r'))
    offsets[1] = 0
  end
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
end

-- Function to find the timeranges (start and end of timepoints) that match a
-- certain pattern, which is the top part of a trace (prefix match).
local function range(...)
  local patt = {...}
  local out = {}
  local matching = false
  for _,tp in ipairs(tps) do
    -- Check if it matches. Default to true if patt happens to be empty.
    local ok = true
    local i = 1
    for pi,p in ipairs(patt) do
      if p == '...' then  -- ... matches the minimum number needed to get to the next one (or 0)
        p = assert(patt[pi+1])
        while i <= #tp.trace and not tp.trace[i]:find('^'..p) do i = i + 1 end
        if i > #tp.trace then ok = false; break end
      elseif i > #tp.trace then  -- If we're out of trace, it doesn't match.
        ok = false; break
      else  -- We have room and a pattern to match, check for a prefix. Eat it if it matches.
        if tp.trace[i]:find('^'..p) then i = i + 1
        else ok = false; break end
      end
    end

    if ok then
      if matching then
        -- If it matches and we were in the middle of a range, extend the range.
        out[#out][2] = tp
      else  -- Otherwise, start a new range.
        out[#out+1] = {tp, tp}
        matching = true
      end
    elseif matching then
      -- Otherwise we've just finished a range, mark it for a new one when another match appears.
      out[#out][2] = tp
      matching = false
    end
  end
  return out
end

-- We want to find the ranges that we care about, and then output the Lua for easy processing.
-- To make it easier, a function to spit bits out.
-- First line is the name of the key, all other lines are the trace pattern.
local function output(fmt)
  local n,p = nil, {}
  for l in fmt:gmatch '[^\n]+' do
    if n then p[#p+1] = l else n = l end
  end
  local ranges = range(table.unpack(p))
  for i,r in ipairs(ranges) do
    ranges[i] = ('{s=%f, e=%f, l=%f}'):format(r[1].time, r[2].time, r[2].time-r[1].time)
  end
  print(n..' = {'..table.concat(ranges, ', ')..'},')
end

-- And here we go!
print 'return {'

-- Entire execution
output 'exec'
-- createIndices is mostly a parallel region, I'm interested in it
output [[symtabCI
...
BAnal::Struct::makeStructure
...
Dyninst::SymtabAPI::Symtab::createIndices]]
-- The original parallelism in Symtab: the DwarfWalker
output [[symtabDW
...
Dyninst::SymtabAPI::DwarfWalker::parse
]]
-- Two ranges within makeStructure. Short and not really our problem, but still parallel.
output [[banal
...
BAnal::Struct::makeStructure
GOMP_parallel
]]
-- Parallel "windup" for ParseAPI. Very highly unbalanced, but also very short.
output [[parseIR
...
Dyninst::ParseAPI::SymtabCodeSource::init_regions
[Gg][Oo][Mm][Pp]_
]]
-- The main parallel region in ParseAPI, the parsing of the frames.
output [[parsePF
...
Dyninst::ParseAPI::Parser::parse_frames
]]
-- Parallel "winddown" for ParseAPI. Has a leftover barrier but otherwise fine.
output [[parseFF
...
Dyninst::ParseAPI::Parser::finalize_funcs
]]

print '}'
