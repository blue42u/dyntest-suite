-- luacheck: std lua53, no global (Tup-Lua)

sclass = 3

local rep = 0
if tup.getconfig 'CRASH_REP' ~= '' then
  rep = assert(math.tointeger(tup.getconfig 'CRASH_REP'),
    'Configuration option CRASH_REP must be a valid integer!')
end
if rep == 0 then return end

tup.rule(forall(function()
  return {
    id = 'Crash', threads=maxthreads,
    cmd = './rep.sh '..rep..' %o %C', redirect = '/dev/null',
    output = 'crashes.%t.%i.log', serialize = true,
  }
end), '^o Concatinated %o^ cat %f > %o', {'crashes.log', serialpost()})

serialfinal()
