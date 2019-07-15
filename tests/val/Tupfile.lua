-- luacheck: std lua53, no global (Tup-Lua)

local llp = 'LD_LIBRARY_PATH=../../external/gcc/lib '
local lds = '../../external/gcc/<build>'
local com = 'valgrind --log-file=%o --suppressions=system.supp'
  ..' --suppressions=toreport.supp'

tup.rule(forall(function(i)
  if i.size > 2 then return end
  return {
    id = 'Memcheck',
    threads = 32,
    cmd = com..' --tool=memcheck %C',
    redirect = '/dev/null',
    output = 'mc/%t.%i.log',
  }
end), '^o Concat %o^ cat %f > %o', 'memcheck.log')

tup.rule(forall(function(i)
  if i.size > 1 then return end
  return {
    id = 'Helgrind',
    threads = 32,
    cmd = llp..com..' --tool=helgrind %C',
    redirect = '/dev/null',
    output = 'hg/%t.%i.log',
    deps = {lds},
  }
end), '^o Concat %o^ cat %f > %o', 'helgrind.log')

-- tup.rule(forall(function(i)
--   if i.size > 1 then return end
--   return {
--     id = 'DRD',
--     threads = 32,
--     cmd = llp..com..' --tool=drd %C',
--     redirect = '/dev/null',
--     output = 'drd/%t.%i.log',
--     deps = {lds},
--   }
-- end), '^o Concat %o^ cat %f > %o', '../drd.log')

local big,bigsize
local massif = forall(function(i, t)
  if i.size > 2 then return end
  local o = {
    id = 'Massif',
    threads = 32,
    cmd = 'valgrind -q --massif-out-file=%o --tool=massif %C',
    redirect = '/dev/null',
    output = 'massif/%t.%i.out',
  }
  if not big or i.size*t.size > bigsize then big,bigsize = o,i.size*t.size end
  return o
end)
for i,f in ipairs(massif) do
  local o = f:gsub('%.out$', '.dump')
  tup.rule(f, '^ Massif Dump %f -> %o^ ms_print %f > %o', o)
  if i == big.idx then
    tup.rule(o, '^ Copy %f -> %o^ cp %f %o', 'massif.dump')
  end
end
