-- luacheck: std lua53, no global (Tup-Lua)

tup.creategitignore()
tup.export 'TMPDIR'

subp = {}

-- Handy helpers for handling subprocesses
local function pclose(f, o)
  local ok,kind,code = f:close()
  if not kind then return
  elseif not ok then
    if kind == 'exit' then
      if o then io.stderr:write(o,'\n') end
      error('Subprocess exited with code '..code)
    elseif kind == 'signal' then error('Subprocess was killed by signal '..code)
    else
      if o then io.stderr:write(o,'\n') end
      error('Subprocess exited in a weird way... '..tostring(kind)..'+'..tostring(code))
    end
  end
end
function subp.exec(cmd)
  local p = io.popen(cmd, 'r')
  local o = p:read 'a'
  pclose(p, o)
  return o
end
function subp.lexec(cmd) return (subp.exec(cmd):gsub('%s+$', '')) end
function subp.plines(cmd, fmt)
  local p = io.popen(cmd, 'r')
  local f,s,v = p:lines(fmt or 'l')
  local bits = {}
  return function(...)
    local x = f(...)
    if x == nil then pclose(p, table.concat(bits, '\n'))
    else table.insert(bits, x) end
    return x
  end, s, v
end
function subp.testexec(cmd)
  local p = io.popen(cmd, 'r')
  for _ in p:lines(1024) do end
  return not not p:close()
end

-- Simple command line constructing functions
function subp.shell(...)
  local function shellw(w)
    if type(w) == 'table' then
      local x = {}
      for i,v in ipairs(w) do x[i] = shellw(v) end
      return table.concat(x, ' ')
    end
    -- Fold any subshells out of sight for the time being
    local subs = {}
    w = w:gsub('`.-`', function(ss)
      subs[#subs+1] = ss
      local id = ('\0%d\0'):format(#subs)
      subs[id] = ss
      return id
    end)
    local quote
    w,quote = w:gsub('[\n$"]', '\\%0')
    if quote == 0 and not w:find '[\\%s]' then quote = false end
    -- Unfold the subshells
    w = w:gsub('\0%d+\0', function(id)
      return quote and subs[id] or '"'..subs[id]..'"'
    end)
    return quote and '"'..w..'"' or w
  end
  local function pre(c)
    local prefix = ''
    if c.env then
      local ord = {}
      for k,v in pairs(c.env) do
        assert(k:find '^[%w_]+$', k)
        ord[k] = k..'='..shellw(v):gsub('?', '$'..k)
        table.insert(ord, k)
      end
      table.sort(ord)
      for i,k in ipairs(ord) do ord[i] = ord[k] end
      prefix = prefix..table.concat(ord, ' ')..' '
    end
    return prefix
  end
  local function post(c)
    local postfix = ''
    if c.onlyout then postfix = postfix..' 2>&1' end
    if c.rein then postfix = postfix..' < '..c.rein end
    if c.reout ~= nil then postfix = postfix..' > '..(c.reout or '/dev/null') end
    if c.reerr ~= nil then postfix = postfix..' 2> '..(c.reerr or '/dev/null') end
    return postfix
  end

  local function command(c)
    local x = {}
    for i,w in ipairs(c) do x[i] = shellw(w) end
    return pre(c)..table.concat(x, ' ')..post(c)
  end
  local pipeline, sequence
  function pipeline(cs)
    if type(cs[1]) == 'string' then return command(cs), true end
    local x = {}
    for i,c in ipairs(cs) do
      local cmd
      x[i],cmd = sequence(c)
      if not cmd then x[i] = '('..x[i]..')' end
    end
    return table.concat(x, ' | ')
  end
  function sequence(cs)
    if type(cs[1]) == 'string' then return command(cs), true end
    local x = {}
    for i,c in ipairs(cs) do x[i] = pipeline(c) end
    return table.concat(x, ' && ')
  end

  return sequence{...}
end
function subp.sexec(...) return subp.exec(subp.shell(...)) end
function subp.slexec(...) return subp.lexec(subp.shell(...)) end
function subp.stestexec(...) return subp.testexec(subp.shell(...)) end
function subp.slines(...) return subp.plines(subp.shell(...)) end
