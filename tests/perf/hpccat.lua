-- Concatinate stats from multiple statistics files, by thread counts.
-- luacheck: std lua53

package.path = '../../external/?.lua;'..package.path
require 'serpent'

local fs = {...}
local out = table.remove(fs, 1)

local data = {}
for _,tfn in ipairs(fs) do
  local nt,fn = tfn:match '(%d+):(.+)'
  assert(nt and fn, tfn)
  nt = tonumber(nt)
  local f = io.open(fn, 'r')
  local x = f:read 'a'
  _,data[nt] = assert(serpent.load(x))
  f:close()
end

local outf = io.open(out, 'w')
outf:write(serpent.block(data, {comment=false}))
outf:close()
