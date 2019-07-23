-- luacheck: std lua53, no global (Tup-Lua)

tup.rule(forall(function(i)
  if i.size > 2 then return end
  local runs = {}
  for idx,c in ipairs{1,2,4,8,16,32} do
    runs[idx] = {
      id = 'Stable ('..c..')', threads = c, cmd = '%C',
      output = '%t.%i/run.'..c, --serialize = true,
    }
  end
  return {
    id = 'Stable (ref)', reference = true, threads = 1, cmd = '%C',
    output = '%t.%i/ref',
  }, table.unpack(runs)
end, function(ins, i, t)
  if #ins == 0 then return end
  if t.outclean then
    for idx, f in ipairs(ins) do
      local o = f..'.clean'
      tup.rule(f, '^o Cleaned %f^ '..t.outclean, o)
      ins[idx] = o
    end
  end
  ins[1] = ins[2]
  local o = t.id..'.'..i.id..'.out'
  tup.rule(ins, '^o Generated %o^ ./diffout.sh '..i.id..' '..t.id..' %f > %o', o)
  return {o}
end), '^o Concatinated %o^ cat %f > %o', 'stable.out')
