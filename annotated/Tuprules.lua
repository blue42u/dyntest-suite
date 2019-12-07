-- luacheck: std lua53, no global (Tup-Lua)

ompcfg = ''
ompcppflags = ''
ompcxxflags = ''
if tup.getconfig 'CXX_DEBUG_ROOT' ~= '' then
  ompcfg = ('@!L!BASE/lib@ @!L!BASE/lib64@ @!L!BASE/lib32@'
    ..' @!I!BASE/include/c++/current@ @!I!BASE/include/c++/current-arch@'
    ..' @!CXXF!-nostdinc++@')
    :gsub('BASE', tostring(tup.getconfig 'CXX_DEBUG_ROOT'))
  ompcppflags = ('-LBASE/lib -LBASE/lib64 -LBASE/lib32'
    ..' -IBASE/include/c++/current -IBASE/include/c++/current-arch')
    :gsub('BASE', tostring(tup.getconfig 'CXX_DEBUG_ROOT'))
  ompcxxflags = '-nostdinc++'
end
