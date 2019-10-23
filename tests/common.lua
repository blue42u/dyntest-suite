-- luacheck: std lua53, no global (Tup-Lua)

function enabled(n, default)
  assert(default ~= nil)
  n = tup.getconfig(n)
  if n == 'y' or n == 'Y' then return true
  elseif n == 'n' or n == 'N' then return false
  elseif n == '' then return not not default
  else error('Configuration option '..n..' must be y/Y or n/N!') end
end

function ruleif(ins, ...)
  if #ins > 0 then tup.rule(ins, ...) end
end

if not ({['']=true, ['0']=true})[tostring(tup.getconfig 'MAX_THREADS')] then
  maxthreads = assert(math.tointeger(tup.getconfig 'MAX_THREADS'),
    'Configuration option MAX_THREADS must be a valid integer!')
else
  maxthreads = 0
  for l in io.lines '/proc/cpuinfo' do
    if l:find '^processor%s*:' then maxthreads = maxthreads + 1 end
  end
  assert(maxthreads ~= 0, 'Error getting thread count!')
end

allbuilds = {}
for _,d in ipairs{
  'external/lzma', 'external/tbb', 'external/boost',
  'external/monitor', 'external/dwarf', 'external/unwind',
  'external/papi', 'external/zlib', 'external/bzip',
  'external/gcc',
  'latest/elfutils', 'latest/dyninst', 'annotated/dyninst',
  'latest/hpctoolkit', 'annotated/hpctoolkit', 'reference/elfutils',
  'reference/dyninst', 'reference/hpctoolkit', 'annotated/elfutils',
  'reference/micro', 'latest/micro', 'annotated/micro',
  'latest/testsuite',
} do
  table.insert(allbuilds, tup.getcwd()..'/../'..d..'/<build>')
end
