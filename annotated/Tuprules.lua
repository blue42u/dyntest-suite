-- luacheck: std lua53, no global (Tup-Lua)

ompcfg = ''
if tup.getconfig 'ENABLE_OMP_DEBUG' ~= '' then
  ompcfg = '@!!'..tup.getconfig 'ENABLE_OMP_DEBUG'..'@'
end
