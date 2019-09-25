-- luacheck: std lua53

package.path = '../external/slaxml/?.lua;' .. package.path
local slax = require 'slaxdom'

-- Read in the part of the XML after the DTD (Slaxml can't handle it yet)
local xml
do
  for l in io.stdin:lines 'l' do if l == ']>' then break end end
  xml = f:read 'a'
end

-- Blow it up into the full DOM
local dom = slax:dom(xml)

-- TODO: Do some editing

-- Spit it back out, as XML
local outxml = slax:xml(dom, {indent=2, sort=true})
io.stdout:write(outxml)
