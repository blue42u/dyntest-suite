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
      f.lname = nil
    end
  end
  assert(filt:close())
  local idx = 1
  for name in io.lines(filtout) do
    lfuncs[idx].name = name
    idx = idx + 1
  end
end

-- Sort the functions by name, so we have a master order for things
table.sort(funcs, function(a, b)
  if not a.name then io.stderr:write(tostring(a.source)) end
  if not b.name then io.stderr:write(tostring(b.source)) end
  return a.name < b.name
end)

-- Print out lines for each function we found
for _,f in ipairs(funcs) do
  print('# '..f.name)
end
