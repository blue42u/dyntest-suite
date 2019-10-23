-- luacheck: std lua53, no global (Tup-Lua)

-- Tether into the normal serialization path
tup.rule('<inputs>', '^o Serialization bridge^ touch %o', {'order_post', '<pre>'})

-- Pack up a tarball for easy transfer of all outputs
tup.rule({'stable/<post>', 'crash/<post>', 'val/<out>', 'perf/<post>'},
  '^o Constructed final output bundle^ ./tarcat.sh %o %<out> %<post>',
  'all.txz')
