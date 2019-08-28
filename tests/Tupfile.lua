-- luacheck: std lua53, no global (Tup-Lua)

-- For each test that has a special input, we do the processing up front
for _,t in ipairs(tests) do if t.input then
  for _,i in ipairs(inputs) do
    local cmds = type(t.input) == 'string' and {[false]=t.input} or t.input
    for m,cmd in pairs(cmds) do
      local ins = {i.fn, extra_inputs=alldeps}
      if i.grouped then cmd, ins[1] = cmd:gsub('%%f', i.fn), nil end
      local fn = 'inputs/'..minihash(t.id..i.id..(m or ''))
      tup.rule(ins, '^o Transformed '..i.id..' for '..t.id
        ..(m and '('..m..')' or '')..'^ '..cmd, {fn, '<inputs>'})
    end
  end
end end

tup.rule('<inputs>', '^o Serialization bridge^ touch %o', {'order_post', '<pre>'})

tup.rule({'stable/<post>', 'crash/<post>', 'val/<out>', 'perf/<post>'},
  '^o Constructed final output bundle^ ./tarcat.sh %o %<out> %<post>',
  'all.txz')
