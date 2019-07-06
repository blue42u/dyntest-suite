#!/usr/bin/env lua5.3

-- Somewhat automatic conversion from Makefiles to Tup rules.
-- Usage: ./make.lua <path/to/source> <path/to/install>

-- Debugging function for outputting info to stderr.
local function p(...)
  local t = {...}
  for i,v in ipairs(t) do t[i] = tostring(v) end
  io.stderr:write(table.concat(t, '\t')..'\n')
end

p 'Hello, world!'
