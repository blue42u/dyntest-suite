-- Emulates the actions of cfgdump, but using only debug info and
-- the RTL source files.

local rtldir,bin = ...
assert(bin and rtldir, "Usage: lua jtdump.lua path/to/rtl/root <binary>")

-- First get a list of all the functions and the files they come from
local funcs,files = {},{}
do
  local curfile, curfunc
  local inside = false
  local dwarf = io.popen('objdump -Wi '..bin..' 2>/dev/null')
  for line in dwarf:lines() do
    if line:find '^%s*<%d+><%x+>:%s*Abbrev Number:%s*%d+%s*%(DW_TAG_%g+%)%s*$' then
      inside = line:match '%(DW_TAG_([%a_]+)%)'
      if inside == 'compile_unit' then
        curfile = nil
      elseif inside == 'subprogram' then
        if curfunc then
          table.insert(funcs, curfunc)
          if not files[curfunc.file] then files[curfunc.file] = {} end
          table.insert(files[curfunc.file], curfunc)
        end
        curfunc = {file = assert(curfile), source = ''}
      end
    elseif line:find '^%s*<%x+>%s*DW_AT_%g+' then
      local attr = assert(line:match 'DW_AT_([%a_]+)', line)
      if inside == 'compile_unit' then
        if attr == 'name' then
          local fn = line:reverse():match '^(.-):[%s%)]':reverse()
          curfile = (curfile or '')..fn
        elseif attr == 'comp_dir' then
          local path = line:reverse():match '^(.-):[%s%)]':reverse()
          curfile = path:gsub('/*$', '/')..(curfile or '')
        end
      elseif inside == 'subprogram' then
        assert(curfile)
        curfunc.source = curfunc.source..line..'\n'
        if attr == 'linkage_name' then
          curfunc.lname = line:reverse():match '^(.-):[%s%)]':reverse()
        elseif attr == 'name' then
          curfunc.name = line:reverse():match '^(.-):[%s%)]':reverse()
        elseif attr == 'low_pc' then
          curfunc.low = tonumber(line:match ':%s*0x(%x+)$', 16)
        elseif attr == 'high_pc' then
          curfunc.high = tonumber(line:match ':%s*0x(%x+)$', 16)
        elseif attr == 'entry_pc' then
          curfunc.entry = tonumber(line:match ':%s*0x(%x+)$', 16)
        elseif attr == 'ranges' then
          error('Full ranges not yet supported!')
        end
      end
    end
  end
  if curfunc then
    table.insert(funcs, curfunc)
    if not files[curfunc.file] then files[curfunc.file] = {} end
    table.insert(files[curfunc.file], curfunc)
  end
  assert(dwarf:close())
end

-- Clean up the ranges, and mark the entry PC if we can
for _,f in ipairs(funcs) do
  if not f.ranges and f.low then
    assert(f.high < f.low, f.low..' '..f.high)
    f.ranges = {{from=f.low, to=f.low+(f.high or 1)}}
    f.low, f.high = nil,nil
  elseif f.ranges then
    assert(not f.low)
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
    if start then
      start = assert(tonumber(start, 16), start)
      if start > 0 and not symbols[start] then
        symbols[start] = {
          name = name,
          size = assert(tonumber(size, 16), size),
        }
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
    table.insert(funcs, {
      lname=sym.name, entry=entry,
      ranges={{from=entry, to=entry+sym.size}},
    })
  end
end

-- ParseAPI can also see PLT entries. So we need to add those in too.
do
  local curentry
  local plt = io.popen("objdump -dj .plt '"..bin.."'")
  for line in plt:lines() do
    if line:find '^%x+%s+<[^@]+@plt>:%s*$' then
      local start,name = line:match '^(%x+)%s+<([^@]+)@plt>:%s*$'
      start = tonumber(start, 16)
      curentry = {
        lname = name, entry=start,
        ranges={{from=start, to=start}},
      }
      table.insert(funcs, curentry)
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
    else curentry = nil end
  end
  assert(plt:close())
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
  if not a.entry then return true end
  if not b.entry then return false end
  return a.entry < b.entry
end)

-- Print out lines for each function we found
for _,f in ipairs(funcs) do
  if f.ranges then
    print(('# %x %s'):format(f.entry, f.name))
    for _,r in ipairs(f.ranges) do
      print(('  range [%x, %x)'):format(r.from, r.to))
    end
  else print(('# Empty %s'):format(f.name)) end
end
