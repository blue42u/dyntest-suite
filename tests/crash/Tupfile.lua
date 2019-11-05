-- luacheck: std lua53, no global (Tup-Lua)

sclass = 3

local rep = 0
if tup.getconfig 'CRASH_REP' ~= '' then
  rep = assert(math.tointeger(tup.getconfig 'CRASH_REP'),
    'Configuration option CRASH_REP must be a valid integer!')
end
if rep == 0 then return end

local sz = math.huge
if tup.getconfig 'CRASH_SZ' ~= '' then
  sz = assert(math.tointeger(tup.getconfig 'CRASH_SZ'),
    'Configuration option CRASH_SZ must be a valid integer!')
end
if sz == -1 then sz = math.huge end

ruleif(forall(function(i)
  if i.size > sz then return end
  return {
    id = 'Crash', threads=maxthreads,
    cmd = './rep.sh '..rep..' %o %C', redirect = '/dev/null',
    output = 'crashes.%t.%i.log', serialize = true,
  }
end), '^o Concatinated %o^ cat %f > %o', {'crashes.log', serialpost()})

serialfinal()
