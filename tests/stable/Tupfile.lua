-- luacheck: std lua53, no global (Tup-Lua)

forall(function()
  local runs = {}
  for idx,i in ipairs{1,2,4,8,16,32} do
    runs[idx] = {
      id = 'Stable ('..i..')', threads = i, cmd = '%C',
      output = '%t.%i/run.'..i,
      noparallel = true,
    }
  end
  return {
    id = 'Stable (ref)', reference = true, threads = 1, cmd = '%C',
    output = '%t.%i/ref',
    noparallel = true,
  }, table.unpack(runs)
end)
