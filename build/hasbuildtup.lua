-- luacheck: std lua53, no global (Tup-Lua)

local hasbt = false
for _,f in ipairs(tup.glob('*.tup')) do
  if f == 'build.tup' then hasbt = true end
end
HAS_BUILD_TUP = hasbt and 'y' or 'n'
