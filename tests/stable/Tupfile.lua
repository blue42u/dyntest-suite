-- luacheck: std lua53, no global (Tup-Lua)

sclass = 1

local function deepcopy(t)
  if type(t) == 'table' then
    local o = {}
    for k,v in pairs(t) do o[k] = deepcopy(v) end
    return o
  else return t end
end

local maxsz = tup.getconfig('STABLE_SZ')
if maxsz ~= '' then
  maxsz = assert(math.tointeger(maxsz),
    'Configuration option STABLE_SZ must be a valid integer!')
  if maxsz == -1 then maxsz = math.huge end
else maxsz = math.huge end

ruleif(forall(function(i, t)
  if t.nooutput then return end
  if not t.modes.ref then return end
  if i.size > maxsz then return end
  local runs = {}
  for idx,c in ipairs{1,2,4,8,16,32} do
    runs[idx] = {
      id = 'Stable ('..c..')', threads = c,
      cmd = '%C || cp failure.txt %o',
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
    local r
    if type(t.outclean) == 'string' then
      r = {
        inputs={extra_inputs={}},
        command=t.outclean,
        outputs={extra_outputs={}},
      }
    else
      r = deepcopy(t.outclean)
      r.inputs = r.inputs or {}
      r.outputs = r.outputs or {}
      assert(#r.inputs == 0 and #r.outputs == 0)
      r.inputs.extra_inputs = r.inputs.extra_inputs or {}
      r.outputs.extra_outputs = r.outputs.extra_outputs or {}
    end
    if not r.command:find '^%s*^' then
      r.command = '^o Cleaned %f^ ./clean.sh %f %o "'..r.command..'"'
    end
    for idx, f in ipairs(ins) do
      local rr = deepcopy(r)
      rr.inputs[1] = f
      rr.outputs[1] = f..'.clean'
      if idx > 2 or t.mpirun then
        table.insert(rr.inputs.extra_inputs, serialend())
      else
        table.insert(rr.outputs.extra_outputs, '../<pre>')
      end
      ins[idx] = rr.outputs[1]
      tup.frule(rr)
    end
  end
  local o = (t.id..'.'..i.id..'.out'):gsub('/','.')
  ins.extra_inputs = serialend()
  tup.rule(ins, '^o Generated %o^ ./diffout.sh \''..i.id..'\' \''..t.id..'\' %f > %o', o)
  return {o}
end), '^o Concatinated %o^ cat %f > %o', {'stable.out', serialpost()})

serialfinal()
