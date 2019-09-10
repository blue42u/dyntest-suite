-- luacheck: std lua53, no global (Tup-Lua)

-- For each test that has a special input, we do the processing up front
local used = {}
for _,t in ipairs(tests) do
  if t.inputtrans then used[t.inputtrans] = true end
end

for u in pairs(used) do
  local t = intrans[u]
  for _,i in ipairs(inputs) do
    local ins = {i.fn, extra_inputs=alldeps}
    local cmd = t.cmd
    if t.grouped then cmd, ins[1] = cmd:gsub('%%f', i.fn), nil end
    local fn = 'inputs/'..minihash(u..i.id)
    tup.rule(ins, '^o Transformed '..u..' '..i.id..'^ '..cmd, {fn, '<inputs>'})
  end
end

tup.rule('<inputs>', '^o Serialization bridge^ touch %o', {'order_post', '<pre>'})

tup.rule({'stable/<post>', 'crash/<post>', 'val/<out>', 'perf/<post>'},
  '^o Constructed final output bundle^ ./tarcat.sh %o %<out> %<post>',
  'all.txz')
