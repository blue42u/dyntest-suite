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
  return tps
end

-- Function to find the timeranges (start and end of timepoints) that match a
-- certain pattern, which is the top part of a trace (prefix match).
local function range(tps, ...)
  local patt = {...}
  local out = {}
  local matching = false
  for _,tp in ipairs(tps) do
    -- Check if it matches. Default to true if patt happens to be empty.
    assert(#tp.trace ~= 0)
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

-- Table with prefix patterns for the regions we care about.
local regions = {
  exec = {},  -- Matches anything, entire trace.
  -- Symtab::createIndices, a parallel "windup" for the DWARF parsing
  symtabCI = {'...', 'Dyninst::SymtabAPI::Symtab::createIndices'},
  -- Symtab::DwarfWalker, the main parallel DWARF parsing operation
  symtabDW = {'...', 'Dyninst::SymtabAPI::DwarfWalker::parse'},
  -- Parser::parse_frame, the main parallel binary parsing.
  parsePF = {'...', 'Dyninst::ParseAPI::Parser::parse_frames'},
}

-- Parse the arguments. First is the output file, rest are databases.
local dbs = {...}
local outfn = table.remove(dbs, 1)

-- Read in each database and process out its ranges for the given regions.
-- Ranges from different databases are matched together, and we error
-- if the counts differ unless they're fully missing.
local stats = {}
for _,db in ipairs(dbs) do
  local tps = timepoint(db, trace(db))
  for k,p in pairs(regions) do
    stats[k] = stats[k] or {}
    local rs = range(tps, table.unpack(p))
    if #rs > 0 then  -- Try to add into the current pile
      if #stats[k] == 0 then  -- Use this as the official count
        for i=1,#rs do stats[k][i] = {} end
      end
      assert(#stats[k] == #rs, 'Mismatching counts for '..k..': '..#stats[k]..' ~= '..#rs..'!')
      for i,r in ipairs(rs) do table.insert(stats[k][i], r) end
    end
  end
  tps = nil  -- luacheck: ignore
  collectgarbage()  -- Try to reduce memory usage if at all possible
end

-- Next parse through each stat and reduce down to its final statistics.
for _,stat in pairs(stats) do
  for idx,rs in ipairs(stat) do
    local o = {avg = 0, sd = 0}
    for _,r in ipairs(rs) do o.avg = o.avg + (r[2].time - r[1].time) end
    o.avg = o.avg / #rs
    for _,r in ipairs(rs) do o.sd = o.sd + (r[2].time - r[1].time - o.avg)^2 end
    o.sd = math.sqrt(o.sd / (#rs - 1))
    stat[idx] = o
  end
end

-- Last, pop open the output file and cough out everything we gained here.
local ord = {}
for k in pairs(stats) do table.insert(ord, k) end
table.sort(ord)
local f = io.open(outfn, 'w')
f:write 'return {\n'
for _,k in ipairs(ord) do
  f:write('  '..k..' = {\n')
  for _,s in ipairs(stats[k]) do
    f:write(('    {avg=%f, sd=%f},\n'):format(s.avg, s.sd))
  end
  f:write '  },\n'
end
f:write '}\n'
f:close()
