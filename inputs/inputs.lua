-- luacheck: std lua53, no global (Tup-Lua)

local cwd = tup.getcwd():gsub('[^/]$', '%0/')

inputs = {}
local function add_inputs(t)
  for _,i in ipairs(t) do
    if i.fn then
      assert(not i.fnstem and not i.fullfn)
      i.fullfn = cwd..i.fn
      i.fn = nil
    end
    if i.fullfn then
      i.modes = {[false]=i.fullfn, ann=i.fullfn, ref=i.fullfn}
      i.fullfn = nil
    end
    if i.fnstem then
      i.modes = {
        [false]=cwd..'latest/'..i.fnstem,
        ann=cwd..'latest/'..i.fnstem,
        ref=cwd..'reference/'..i.fnstem,
      }
      i.fnstem, i.grouped = nil, true
    end
    table.insert(inputs, i)
  end
end

if not enabled('ONLY_EXTERNAL', false) then add_inputs{
  -- Some simple test binaries taken from the build outputs
  { id = 'libasm', grouped = true,
    fn = '../latest/elfutils/install/lib/libasm.so',
    size = 1, kind = 'binary',
  },
  { id = 'libdw', grouped = true,
    fn = '../latest/elfutils/install/lib/libdw.so',
    size = 1, kind = 'binary',
  },
  { id = 'libcommon', grouped = true,
    fn = '../latest/dyninst/install/lib/libcommon.so',
    size = 2, kind = 'binary',
  },
  { id = 'libdyninst', grouped = true,
    fn = '../latest/dyninst/install/lib/libdyninstAPI.so',
    size = 3, kind = 'binary',
  },
  { id = 'hpcstruct', grouped = true,
    fn = '../latest/hpctoolkit/install/libexec/hpctoolkit/hpcstruct-bin',
    size = 3, kind = 'binary',
  },
  -- Some simple test traces, using hpcstruct and some specialized ones.
  { id = 'hello', fnstem = 'hello.tar',
    size = 1, kind = 'trace',
  },
  { id = 'parvecsum', fnstem = 'parvecsum.tar',
    size = 1, kind = 'trace',
  },
  { id = 'ssort', fnstem = 'ssort.tar',
    size = 2, kind = 'trace',
  },
  { id = 'fib', fnstem = 'fib.tar',
    size = 2, kind = 'trace',
  },
  { id = 'hpcstruct/libcommon', fnstem = 'hpcstruct.libcommon.tar',
    size = 3, kind = 'trace',
  },
} end

-- Pull in the manually-given inputs
for _,s in ipairs{'1', '2', '3', 'huge'} do
  local sz = tonumber(s) or math.huge
  local function kind(id)
    if subp.stestexec{
      {'readelf', '-h', 'inputs/'..s..'/'..id, reerr = false, reout = false}
    } then return 'binary'
    elseif subp.stestexec{
      {'tar', '--test-label', '-af', 'inputs/'..s..'/'..id, reerr=false, reout=false}
    } then return 'trace'
    else error('Unable to determine kind for inputs/'..s..'/'..id) end
  end
  for _,f in ipairs(tup.glob(cwd..s..'/*')) do
    local id = f:match '[^/]+$'
    if id ~= '.gitignore' then
      local rf = tup.glob(cwd..s..'.ref/'..id)[1]
      if rf then
        add_inputs{{id = id, size = sz, kind = kind(id),
          modes = {[false]=f, ann=f, ref=rf},
        }}
      else
        add_inputs{{id = id, fullfn = f, size = sz, kind = kind(id)}}
      end
    end
  end
end

-- Sort the inputs before letting anyone else work with 'em
table.sort(inputs, function(a,b)
  if a ~= b then assert(a.id ~= b.id, 'Id collision: '..a.id) end
  return a.id < b.id
end)
