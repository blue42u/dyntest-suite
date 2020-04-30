-- luacheck: std lua53, no global

-- Same form as the other buildscripts, but we issue the rules ourself.

local cwd = tup.getcwd()
local boost = cwd..'/../external/boost'
local tbb = cwd..'/../external/tbb'

local b = '/<build>'
local i = '/install/include'
local l = '/install/lib'

function cfgtests(o)
  local ex = {boost..b, tbb..b, o.dyninst..b}
  local cf = (o.cppflags or '')..' '..(o.cxxflags or '')
    ..' -I'..boost..i..' -I'..tbb..i..' -I'..o.dyninst..i
    ..' -L'..o.dyninst..l..' -L'..boost..l..' -g -O2'
  local lf = '-Wl,-rpath,`realpath '..boost..l..'`:`realpath '..tbb..l..'`'
    ..':`realpath '..o.dyninst..l..'`'

  tup.rule({cwd..'/cfgtests/cfgdump.cpp', extra_inputs=ex},
    '^o Compiled %o^ c++ '..cf..' -o %o %f '..lf
    ..' -lsymtabAPI -lparseAPI -lboost_system',
    {'cfgdump', '<build>'})
end
