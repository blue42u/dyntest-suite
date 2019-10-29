-- luacheck: std lua53, no global (Tup-Lua)

-- Factor out the common bits
local function hpcrun(c)
  local r = {inputs={extra_inputs={}}, outputs={extra_outputs={'<all>'}}}
  table.move(allbuilds, 1,#allbuilds, #r.inputs.extra_inputs+1, r.inputs.extra_inputs)
  if c.deps then
    table.move(c.deps, 1,#c.deps, #r.inputs.extra_inputs+1, r.inputs.extra_inputs)
  end

  local dir,did
  if c.mode == false or c.mode == 'ann' then dir,did = 'latest',''
  elseif c.mode == 'ref' then dir,did = 'reference',' (ref)'
  else error(c.mode) end
  r.outputs[1] = dir..'/'..c.id..'.tar'
  table.insert(r.inputs.extra_inputs, '../'..dir..'/hpctoolkit/<build>')

  local events = '-e REALTIME@100'
  if c.events then
    events = {}
    for i,e in ipairs(c.events) do events[i] = '-e '..e end
    events = table.concat(events, ' ')
  end

  r.command = '^o Trace '..c.id..did..'^ ../tartrans.sh '
            ..'../'..dir..'/hpctoolkit/install/bin/hpcrun.real '
            ..'-o @@%o -t '..events..' '
            ..c.cmd

  tup.frule(r)
end

-- Compile the little example programs
for _,f in ipairs{'fib', 'vecsum', 'parvecsum'} do
  tup.rule('src/'..f..'.c', 'cc -o %o -O3 -g -pthread %f', 'src/'..f)
end
tup.rule({'src/sort1.cpp','src/sort2.cpp'}, 'c++ -o %o -O1 -g %f', 'src/ssort')

-- First the ones that don't need to be serialized
hpcrun{ id = 'fib', mode=false, deps={'src/fib'}, cmd='src/fib > /dev/null' }
hpcrun{ id = 'fib', mode='ref', deps={'src/fib'}, cmd='src/fib > /dev/null' }
hpcrun{ id = 'vecsum', mode=false, deps={'src/vecsum'}, cmd='src/vecsum > /dev/null' }
hpcrun{ id = 'vecsum', mode='ref', deps={'src/vecsum'}, cmd='src/vecsum > /dev/null' }
hpcrun{ id = 'parvecsum', mode=false, deps={'src/parvecsum'}, cmd='src/parvecsum > /dev/null' }
hpcrun{ id = 'parvecsum', mode='ref', deps={'src/parvecsum'}, cmd='src/parvecsum > /dev/null' }
hpcrun{ id = 'ssort', mode=false, events={'REALTIME@20000'}, deps={'src/ssort'}, cmd='src/ssort > /dev/null' }
hpcrun{ id = 'ssort', mode='ref', events={'REALTIME@20000'}, deps={'src/ssort'}, cmd='src/ssort > /dev/null' }
hpcrun{ id = 'hpcstruct.libcommon', mode = 'ref',
  cmd = '../reference/hpctoolkit/install/bin/hpcstruct.real -o /dev/null '
      ..'../reference/dyninst/install/lib/libcommon.so',
}

-- Then the ones that do
hpcrun{ id = 'hpcstruct.libcommon', mode = false, serialize = true,
  cmd = '../latest/hpctoolkit/install/bin/hpcstruct.real -o /dev/null '
      ..'-j '..maxthreads..' --jobs-symtab '..maxthreads..' '
      ..'../reference/dyninst/install/lib/libcommon.so',
}
