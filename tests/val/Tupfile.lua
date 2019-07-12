-- luacheck: std lua53, no global (Tup-Lua)

local com = 'valgrind --log-file=%o --suppressions=system.supp'

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
  if i.size > 3 then return end
  return {
    id = 'Helgrind',
    threads = 32,
    cmd = com..' --tool=helgrind %C',
    redirect = '/dev/null',
    output = 'hg/%t.%i.log',
  }
end), '^o Concat %o^ cat %f > %o', 'helgrind.log')

-- tup.rule(forall(function(i)
--   if i.size > 1 then return end
--   return {
--     id = 'DRD',
--     threads = 32,
--     cmd = com..' --tool=drd %C',
--     redirect = '/dev/null',
--     output = 'drd/%t.%i.log',
--   }
-- end), '^o Concat %o^ cat %f > %o', '../drd.log')

for _,f in ipairs(forall(function(i)
  if i.size > 2 then return end
  return {
    id = 'Massif',
    threads = 32,
    cmd = 'valgrind --log-file=/dev/null --massif-out-file=%o --tool=massif %C',
    redirect = '/dev/null',
    output = 'massif/%t.%i.out',
  }
end)) do
  tup.rule(f, '^ Massif Dump %f -> %o^ ms_print %f > %o', f:gsub('%.out$', '.dump'))
end
