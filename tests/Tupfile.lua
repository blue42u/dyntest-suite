-- luacheck: std lua53, no global (Tup-Lua)

local function tcopy(t)
  return table.move(t, 1,#t, 1, {})
end

-- For each test that has a special input, we do the processing up front.
-- First get a list of all the transformations we need to do.
local used = {}
for _,t in ipairs(tests) do
  if t.inputtrans then used[t.inputtrans] = true end
end
local trans = {}
for u in pairs(used) do table.insert(trans, u) end
table.sort(trans)
for i,t in ipairs(trans) do
  trans[i] = intrans[t]
  trans[i].id = t
end

-- Common function for all the easy components.
local function transrule(t, i)
  local o = {}
  o.inputs = {i.fn, extra_inputs=eis}
  o.command = t.cmd
  if t.grouped then o.command,o.inputs[1] = o.command:gsub('%%f', i.fn), nil end
  o.command = '^o Transformed '..t.id..' '..i.id..'^ '..o.command
  o.outputs = {'inputs/'..minihash(t.id..i.id), '<inputs>'}
  return o
end

-- First pass, handle all the ones that can be done in parallel
local predeps = tcopy(alldeps)
for _,t in ipairs(trans) do if not t.serialize then
  for _,i in ipairs(inputs) do
    local r = transrule(t, i)
    table.insert(predeps, r.outputs[1])
    tup.frule(r)
  end
end end

-- Second pass, handle all the ones that have to be done in serial.
for _,t in ipairs(trans) do if t.serialize then
  for _,i in ipairs(inputs) do
    local r = transrule(t, i)
    r.extra_inputs = predeps
    tup.frule(r)  -- Now we can change predeps, already read into the db
    table.insert(predeps, r.outputs[1])
  end
end end

-- Tether into the normal serialization path
tup.rule('<inputs>', '^o Serialization bridge^ touch %o', {'order_post', '<pre>'})

-- Pack up a tarball for easy transfer of all outputs
tup.rule({'stable/<post>', 'crash/<post>', 'val/<out>', 'perf/<post>'},
  '^o Constructed final output bundle^ ./tarcat.sh %o %<out> %<post>',
  'all.txz')
