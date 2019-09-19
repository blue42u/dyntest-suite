-- luacheck: std lua53, no global (Tup-Lua)

sclass = 1

if enabled('STABLE', true) then
ruleif(forall(function(_, t)
  if t.nooutput then return end
  if not t.modes.ref then return end
  local runs = {}
  for idx,c in ipairs{1,2,4,8,16,32} do
    runs[idx] = {
      id = 'Stable ('..c..')', threads = c,
      cmd = '%C || echo "==FAILURE==" > %o',
      output = '%t.%i/run.'..c, serialize = c > 1,
    }
  end
  return {
    id = 'Stable (ref)', threads = 1, cmd = '%C',
    output = '%t.%i/ref', mode = 'ref',
  }, table.unpack(runs)
end, function(ins, i, t)
  if #ins == 0 then return end
  if t.unstable then return end
  if t.outclean then
    for idx, f in ipairs(ins) do
      local o = f..'.clean'
      tup.rule({f, extra_inputs=serialend()}, '^o Cleaned %f^ '..t.outclean, o)
      ins[idx] = o
    end
  end
  local o = t.id..'.'..i.id..'.out'
  ins.extra_inputs = serialend()
  tup.rule(ins, '^o Generated %o^ ./diffout.sh '..i.id..' '..t.id..' %f > %o', o)
  return {o}
end), '^o Concatinated %o^ cat %f > %o', {'stable.out', serialpost()})
end

serialfinal()
