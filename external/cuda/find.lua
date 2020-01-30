-- luacheck: std lua53, no global (Tup-lua)

if not externalProjects then externalProjects = {} end
externalProjects.cuda = {}

-- Very simple, just let the user decide for us.
externalProjects.cuda.libDir = tostring(tup.getconfig 'CUDA_LIBDIR')
externalProjects.cuda.rootDir = tostring(tup.getconfig 'CUDA_ROOTDIR')
if externalProjects.cuda.libDir == '' and externalProjects.cuda.rootDir == '' then
  externalProjects.cuda = nil
  return
elseif externalProjects.cuda.libDir == '' then
  externalProjects.cuda.libDir = externalProjects.cuda.rootDir:gsub('/?$', '/')..'lib/'
elseif externalProjects.cuda.libDir == '!' then
  -- Magic for empty path
  externalProjects.cuda.libDir = ''
end
