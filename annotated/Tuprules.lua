-- luacheck: std lua53, no global (Tup-Lua)

ompcfg = ''
if tup.getconfig 'CXX_DEBUG_ROOT' ~= '' then
  ompcfg = ('@!L!BASE/lib@ @!L!BASE/lib64@ @!L!BASE/lib32@'
    ..' @!I!BASE/include/c++/current@ @!I!BASE/include/c++/current-arch@'
    ..' @!CXXF!-nostdinc++@')
    :gsub('BASE', tostring(tup.getconfig 'CXX_DEBUG_ROOT'))
end
