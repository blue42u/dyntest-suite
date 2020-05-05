-- Emulates the actions of cfgdump, but using only debug info and
-- the RTL source files.

local rtldir,bin = ...
assert(bin and rtldir, "Usage: lua jtdump.lua path/to/rtl/root <binary>")

-- First get a list of all the functions and the files they come from
local funcs = {}
do
  -- Load in the ranges, so we can build the full ranges.
  local ranges = {}
  local dwarf = io.popen("objdump -WR '"..bin.."'")
  for line in dwarf:lines() do
    local offset, start, fin = line:match '^%s*(%x+)%s+(%x+)%s+(%x+)%s*$'
    if offset then
      offset,start,fin = tonumber(offset,16),tonumber(start,16),tonumber(fin,16)
      ranges[offset] = ranges[offset] or {}
      table.insert(ranges[offset], {from=start, to=fin})
    end
  end
  assert(dwarf:close())

  -- Read the .debug_info to find the functions. This'll get the ones that are
  -- present from the user's perspective
  local curfile, curfunc
  local inside = false
  local origins = {}
  dwarf = io.popen('objdump -Wi '..bin..' 2>/dev/null')
  for line in dwarf:lines() do
    if line:find '^%s*<%d+><%x+>:%s*Abbrev Number:%s*%d+%s*%(DW_TAG_%g+%)%s*$' then
      inside = line:match '%(DW_TAG_([%a_]+)%)'
      if inside == 'compile_unit' then
        curfile = nil
      elseif inside == 'subprogram' then
        if curfunc and (curfunc.low or curfunc.ranges) then
          table.insert(funcs, curfunc)
        end
        local ref = tonumber(line:match '<%d+><(%x+)>', 16)
        curfunc = {file = assert(curfile), source = '', jtables={}}
        origins[ref] = curfunc
      end
    elseif line:find '^%s*<%x+>%s*DW_AT_%g+' then
      local attr = assert(line:match 'DW_AT_([%a_]+)', line)
      if inside == 'compile_unit' then
        if attr == 'name' then
          local fn = line:reverse():match '^(.-)%s*:[%s%)]':reverse()
          curfile = (curfile or '')..fn
        elseif attr == 'comp_dir' then
          local path = line:reverse():match '^(.-)%s*:[%s%)]':reverse()
          curfile = path:gsub('/*$', '/')..(curfile or '')
        end
      elseif inside == 'subprogram' then
        assert(curfile)
        curfunc.source = curfunc.source..line..'\n'
        if attr == 'linkage_name' then
          curfunc.lname = line:reverse():match '^(.-)%s*:':reverse()
        elseif attr == 'name' then
          curfunc.name = line:reverse():match '^(.-)%s*:':reverse()
        elseif attr == 'abstract_origin' then
          local o = tonumber(line:match '<0x(%x+)>$', 16)
          curfunc.name = origins[o].name
          curfunc.lname = origins[o].lname
          curfunc.file = origins[o].file
        elseif attr == 'low_pc' then
          curfunc.low = tonumber(line:match ':%s*0x(%x+)$', 16)
        elseif attr == 'high_pc' then
          curfunc.high = tonumber(line:match ':%s*0x(%x+)$', 16)
        elseif attr == 'entry_pc' then
          curfunc.entry = tonumber(line:match ':%s*0x(%x+)$', 16)
        elseif attr == 'ranges' then
          local offset = tonumber(line:match ':%s*0x(%x+)$', 16)
          if not ranges[offset] then error('Malformed ranges entry!') end
          curfunc.ranges = ranges[offset]
          curfunc.entry = curfunc.ranges[1].from
          ranges[offset] = nil
        end
      end
    end
  end
  if curfunc then
    table.insert(funcs, curfunc)
  end
  assert(dwarf:close())
end

-- Clean up the ranges, and mark the entry PC if we can
for _,f in ipairs(funcs) do
  if not f.ranges and f.low then
    f.ranges = {{from=f.low, to=f.low+(f.high or 1)}}
    f.low, f.high = nil,nil
  elseif f.ranges then
    assert(not f.low, f.low)
    table.sort(f.ranges, function(a,b) return a.from < b.from end)
    local fin = f.ranges[1].from-1
    for _,r in ipairs(f.ranges) do
      if r.from == fin then io.stderr:write("Nonoptimal range detected in "..f.name.."\n")
      elseif r.from < fin then io.stderr:write("Overlapping ranges in "..f.name.."\n")
      end
      fin = r.to
    end
  end
  if not f.entry and f.ranges then
    f.entry = f.ranges[1].from
  end
end

-- ParseAPI uses the names from .symtab, so rename functions
-- based on their entry point. Also add any missing functions.
do
  local symbols = {}  -- Entry PC -> {name=, size=}
  local symtab = io.popen("objdump -t '"..bin.."'")
  for line in symtab:lines() do
    local start,size,name = line:match '^(%x+)[%a%s]+F%s+%g+%s+(%x+)%s+.*%f[%S](%g+)$'
    start = start and assert(tonumber(start, 16), start)
    if start and start > 0 then
      name = name:match '^([^@]+)@@' or name
      if not symbols[start] then
        symbols[start] = {
          name = name,
          size = assert(tonumber(size, 16), size),
        }
      elseif name < symbols[start].name then
        symbols[start].name = name
      end
    end
  end
  assert(symtab:close())

  for _,f in ipairs(funcs) do
    if symbols[f.entry] then
      f.lname = symbols[f.entry].name
      symbols[f.entry] = nil
    end
  end

  for entry,sym in pairs(symbols) do
    local to = entry + sym.size
    if sym.size == 0 then
      -- Sometimes this happens, and its a pain. There's probably an easier
      -- way, for now just use the disassembly.
      local dasm = io.popen("objdump --disassemble="..sym.name.." '"..bin.."'")
      for line in dasm:lines() do
        local addr,bytes = line:match '^%s+(%x+):%s*([%x%s]+)'
        if addr then
          addr = tonumber(addr, 16)
          to = addr
          for b in bytes:gmatch '%x%x%f[%s\0]' do
            addr = addr + 1
            if b ~= '00' then to = addr end
          end
        end
      end
      assert(dasm:close())
    end
    table.insert(funcs, {
      lname=sym.name, entry=entry,
      ranges={{from=entry, to=to}},
      jtables={},
    })
  end
end

-- By this point, we have lnames for most things. Since the RTL uses those
-- we can read assocate it now.
do
  local files = {}
  for _,f in ipairs(funcs) do if f.file then files[f.file] = true end end

  -- Then read in all the RTL files we have available, and break them up by the
  -- function headers.
  for fn in pairs(files) do
    local f,err = io.open(rtldir..fn..'.318r.dfinish')
    if not f then
      io.stderr:write('Unable to read RTL: `'..err..'\'\n')
    else
      local ft = {}
      files[fn] = ft
      local cur = nil
      for line in f:lines 'L' do
        if line:find '^;;' then
          cur = assert(line:match '^;; Function%s*(%S+)', line)
        elseif cur then
          ft[cur] = (ft[cur] or '')..line
        end
      end
      f:close()
    end
  end

  -- Then go through the functions again, and try to associate with the
  -- RTL blobs. If we can.
  for _,f in ipairs(funcs) do
    f.rtl = files[f.file] and (files[f.file][f.lname] or files[f.file][f.name])
  end
end

-- Convert RTL blobs into jump table entries.
for _,f in ipairs(funcs) do if f.rtl then
  f.callsReturn = {}
  for insr in f.rtl:gmatch '%b()' do
    local opcode = assert(insr:match '^%(([%a_]+)', insr)
    if opcode == 'jump_table_data' then
      local targets = {}
      for t in assert(insr:match '%b[]', insr):gmatch '%b()' do
        targets[t] = true
      end
      local cnt = 0
      for _ in pairs(targets) do cnt = cnt + 1 end
      table.insert(f.jtables, cnt)
    elseif opcode == 'call_insn' then
      table.insert(f.callsReturn, not insr:find 'REG_NORETURN')
    end
  end
end end

-- ParseAPI can also see PLT entries. So we need to add those in too.
do
  -- Scan for the current set of claimed entry points
  local entries = {}
  for _,f in ipairs(funcs) do
    if f.entry then entries[f.entry] = f end
  end
  for _,sec in ipairs{'.plt', '.plt.got'} do
    local curentry
    local plt = io.popen("objdump -dj "..sec.." '"..bin.."'")
    for line in plt:lines() do
      if line:find '^%x+%s+<[^@]+@plt>:%s*$' then
        local start,name = line:match '^(%x+)%s+<([^@]+)@plt>:%s*$'
        start = tonumber(start, 16)
        if entries[start] then
          curentry = entries[start]
          for k in pairs(curentry) do curentry[k] = nil end
        else
          curentry = {}
          table.insert(funcs, curentry)
          entries[start] = curentry
        end
        curentry.lname = name
        curentry.entry = start
        curentry.ranges = {{from=start, to=start}}
        curentry.jtables = {-1}
      elseif line:find '^%s+%x+:' and curentry then
        local addr,bytes,instr = line:match '^%s+(%x+):%s*([%x%s]+)(%g+)'
        addr = tonumber(addr, 16)
        local nonffaddr = addr
        for b in bytes:gmatch '%x%x%f[%s\0]' do
          if b == 'ff' then addr = addr + 1
          else nonffaddr,addr = addr+1,addr+1 end
        end
        curentry.ranges[1].to = nonffaddr
        if instr:find '^jmp' then curentry = nil end
      end
    end
    assert(plt:close())
  end
end

-- Sometimes some of the ranges for a function are actually part of an outlined
-- "cold" version. Since by this point they've been claimed already, remove
-- them from their original functions.
do
  local entries = {}
  for _,f in ipairs(funcs) do
    if f.entry then entries[f.entry] = f end
  end
  for _,f in ipairs(funcs) do
    local torm = {}
    for idx,r in ipairs(f.ranges or {}) do
      local o = entries[r.from]
      if o ~= f then
        assert(o.lname == f.lname..'.cold',
          ('%s ~= %s.cold for [%x,%x)'):format(o.lname, f.lname, r.from, r.to))
        table.insert(torm, idx)
      end
    end
    assert(#torm <= 1, #torm)  -- Cold blobs should only need one range
    if torm[1] then table.remove(f.ranges, torm[1]) end
  end
end

-- ParseAPI can see when some "padding" instructions are jumped over within
-- a range. We do our best to snip out ranges likely to be jumped over.
do
  -- First mark down where all the ranges live. Also check that we don't have
  -- any double-claimed ranges.
  local ranges,origins,claimed = {},{},{}
  for _,f in ipairs(funcs) do
    for _,r in ipairs(f.ranges or {}) do
      local rstr = ('jj'):pack(r.from, r.to)
      if claimed[rstr] then
        error(('Multiple functions claim [%x,%x): %s and %s'):format(
          r.from, r.to, origins[rstr].lname, f.lname))
      end
      claimed[rstr] = f
      origins[r] = f
      table.insert(ranges, r)
    end
  end

  -- Sort the origins, and make sure they're actually non-overlapping.
  table.sort(ranges, function(a, b)
    if a.to <= b.from then return true end
    if b.to <= a.from then return false end
    if a == b then return false end
    error(('Overlapping ranges: [%x,%x) (%q) and [%x,%x) (%q)'):format(a.from, a.to,
      ('jj'):pack(a.from,a.to), b.from, b.to, ('jj'):pack(b.from,b.to)))
  end)

  local function indexof(t, x)
    for idx, y in ipairs(t) do
      if y == x then return idx end
    end
  end

  -- Disassemble the whole thing and split ranges as we go.
  local cur = 1
  local ingap = false
  local maybeunbounded = true
  local callpos = {}
  local dasm = io.popen("objdump -d '"..bin.."'")
  for line in dasm:lines() do
    local addr,instr = line:match '^%s+(%x+):%s*[%x%s]+%s(.*)'
    if addr then
      addr = tonumber(addr, 16)
      -- If we've overstepped our range, go to the next.
      while ranges[cur] and ranges[cur].to <= addr do cur = cur + 1 end
      if not ranges[cur] then break end  -- We've walked off what we know
      if ranges[cur].from <= addr then  -- Only continue if we're in a range
        if instr:find '^call' or instr:find '^jmp[^<]+<[^>+]+>' then
          if ingap == true then ranges[cur].from = addr end
          ingap = false

          -- Calls are weird, they don't always return. So we try to match up
          -- with the RTL to figure them out.
          local o = origins[ranges[cur]]
          if o.callsReturn then
            if o.callsReturn[callpos[o] or 1] == false then
              ingap = 'start'
            end
            callpos[o] = (callpos[o] or 1) + 1
          end
          -- No matter what the RTL says, a jump is non-returning
          if instr:find '^jmp' then ingap = 'start' end
        elseif instr:find '^jmp' or instr:find '^ret' then
          -- Fixup the last gap
          if ingap == true then ranges[cur].from = addr end
          -- Gaps can start right after a jump.
          ingap = 'start'
        elseif instr:find '^nop' or instr:find '^xchg%s+%%ax,%%ax' or instr == '' then
          -- Its a no-op. Add or extend the gap.
          if ingap == 'start' then  -- Split this range into two.
            table.insert(ranges, cur+1, {from=addr, to=ranges[cur].to})
            local o = origins[ranges[cur]]
            origins[ranges[cur+1]] = o
            table.insert(o.ranges, indexof(o.ranges, ranges[cur])+1, ranges[cur+1])
            ranges[cur].to = addr
            ingap = true
          end
        elseif ingap then  -- Its not a no-op. End the gap right here.
          if ingap == true then ranges[cur].from = addr end
          ingap = false
        end

        -- While we're here, check for a somewhat obvious unbounded jump
        if maybeunbounded and instr:find '^jmpq%s+%*%%rax'
          and (#origins[ranges[cur]].jtables == 0
          or origins[ranges[cur]].jtables.faked) then
          table.insert(origins[ranges[cur]].jtables, -1)
          origins[ranges[cur]].jtables.faked = true
        end
        maybeunbounded = not instr:find '^add'
      end
    else
      addr = line:match '^(%x+)%s+<[^>]+>:%s*$'
      if addr then  -- Function start/end
        addr = tonumber(addr, 16)
        while ranges[cur] and ranges[cur].to <= addr do cur = cur + 1 end
        if not ranges[cur] then break end  -- We've walked off what we know
        if ingap == true then  -- If the last range of a function is a no-op, just remove it
          local o = origins[ranges[cur-1]]
          table.remove(o.ranges, indexof(o.ranges, ranges[cur-1]))
        end
        ingap = false
      end
    end
  end
  assert(dasm:close())
end

-- Demangle any function names that need it. Done in post to use only one
-- c++filt process.
do
  local filtout = os.tmpname()
  local filt = io.popen("c++filt -n > '"..filtout.."'", 'w')
  local lfuncs = {}
  for _,f in ipairs(funcs) do
    if f.lname then
      table.insert(lfuncs, f)
      filt:write(f.lname, '\n')
    end
  end
  assert(filt:close())
  local idx = 1
  for name in io.lines(filtout) do
    lfuncs[idx].name = name
    idx = idx + 1
  end
end

-- Sort the functions by entry PC, so we have a master order for things
table.sort(funcs, function(a, b)
  if a.entry and b.entry then return a.entry < b.entry end
  if not a.entry and not b.entry then return a.name < b.name end
  if a.entry then return false end
  if b.entry then return true end
end)

-- Print out lines for each function we found
for _,f in ipairs(funcs) do
  if f.ranges then
    print(('# %x %s'):format(f.entry, f.name))
    for _,r in ipairs(f.ranges) do
      print(('  range [%x, %x)'):format(r.from, r.to))
    end
    for _,t in ipairs(f.jtables) do
      if t < 0 then print('  Unbounded jump table')
      else print(('  Jump table with %d targets'):format(t)) end
    end
  end
end
