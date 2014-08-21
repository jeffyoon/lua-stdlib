local hell      = require "specl.shell"
local inprocess = require "specl.inprocess"
local std       = require "specl.std"

package.path = std.package.normalize ("lib/?.lua", "lib/?/init.lua", package.path)


-- Allow user override of LUA binary used by hell.spawn, falling
-- back to environment PATH search for "lua" if nothing else works.
local LUA = os.getenv "LUA" or "lua"


-- A copy of base.lua:prototype, so that an unloadable base.lua doesn't
-- prevent everything else from working.
function prototype (o)
  return (getmetatable (o) or {})._type or io.type (o) or type (o)
end


-- Error message specifications use this to shorten argument lists.
-- Copied from functional.lua to avoid breaking all tests if functional
-- cannot be loaded correctly.
function bind (f, fix)
  return function (...)
           local arg = {}
           for i, v in pairs (fix) do
             arg[i] = v
           end
           local i = 1
           for _, v in pairs {...} do
             while arg[i] ~= nil do i = i + 1 end
             arg[i] = v
           end
           return f (unpack (arg))
         end
end


local function mkscript (code)
  local f = os.tmpname ()
  local h = io.open (f, "w")
  h:write (code)
  h:close ()
  return f
end


--- Run some Lua code with the given arguments and input.
-- @string code valid Lua code
-- @tparam[opt={}] string|table arg single argument, or table of
--   arguments for the script invocation.
-- @string[opt] stdin standard input contents for the script process
-- @treturn specl.shell.Process|nil status of resulting process if
--   execution was successful, otherwise nil
function luaproc (code, arg, stdin)
  local f = mkscript (code)
  if type (arg) ~= "table" then arg = {arg} end
  local cmd = {LUA, f, unpack (arg)}
  -- inject env and stdin keys separately to avoid truncating `...` in
  -- cmd constructor
  cmd.env = { LUA_PATH=package.path, LUA_INIT="", LUA_INIT_5_2="" }
  cmd.stdin = stdin
  local proc = hell.spawn (cmd)
  os.remove (f)
  return proc
end


--- Concatenate the contents of listed existing files.
-- @string ... names of existing files
-- @treturn string concatenated contents of those files
function concat_file_content (...)
  local t = {}
  for _, name in ipairs {...} do
    h = io.open (name)
    t[#t + 1] = h:read "*a"
  end
  return table.concat (t)
end


local function tabulate_output (code)
  local proc = luaproc (code)
  if proc.status ~= 0 then return error (proc.errout) end
  local r = {}
  proc.output:gsub ("(%S*)[%s]*",
    function (x)
      if x ~= "" then r[x] = true end
    end)
  return r
end


--- Return a formatted bad argument string.
-- @tparam table M module table
-- @string fname base-name of the erroring function
-- @int i argument number
-- @string want expected argument type
-- @string[opt="no value"] got actual argument type
-- @usage
--   expect (f ()).to_error (badarg (fname, mname, 1, "function"))
local function badarg (mname, fname, i, want, got)
  if want == nil then i, want = i - 1, i end

  if got == nil and type (want) == "number" then
    local s = "too many arguments to '%s.%s' (no more than %d expected, got %d)"
    return string.format (s, mname, fname, i, want)
  end
  return string.format ("bad argument #%d to '%s.%s' (%s expected, got %s)",
                        i, mname, fname, want, got or "no value")
end


--- Initialise custom function and argument error handlers.
-- @tparam table M module table
-- @string fname function name to bind
-- @treturn string *fname*
-- @treturn function `M[fname]` if any, otherwise `nil`
-- @treturn function badarg with *M* and *fname* prebound
-- @treturn function toomanyarg with *M* and *fname* prebound
function init (M, mname, fname)
  return M[fname], bind (badarg, {mname, fname})
end


--- Show changes to tables wrought by a require statement.
-- There are a few modes to this function, controlled by what named
-- arguments are given.  Lists new keys in T1 after `require "import"`:
--
--     show_apis {added_to=T1, by=import}
--
-- List keys returned from `require "import"`, which have the same
-- value in T1:
--
--     show_apis {from=T1, used_by=import}
--
-- List keys from `require "import"`, which are also in T1 but with
-- a different value:
--
--     show_apis {from=T1, enhanced_by=import}
--
-- List keys from T2, which are also in T1 but with a different value:
--
--     show_apis {from=T1, enhanced_in=T2}
--
-- @tparam table argt one of the combinations above
-- @treturn table a list of keys according to criteria above
function show_apis (argt)
  local added_to, from, not_in, enhanced_in, enhanced_after, by =
    argt.added_to, argt.from, argt.not_in, argt.enhanced_in,
    argt.enhanced_after, argt.by

  if added_to and by then
    return tabulate_output ([[
      local before, after = {}, {}
      for k in pairs (]] .. added_to .. [[) do
        before[k] = true
      end

      local M = require "]] .. by .. [["
      for k in pairs (]] .. added_to .. [[) do
        after[k] = true
      end

      for k in pairs (after) do
        if not before[k] then print (k) end
      end
    ]])

  elseif from and not_in then
    return tabulate_output ([[
      local from = ]] .. from .. [[
      local M = require "]] .. not_in .. [["

      for k in pairs (M) do
	-- M[1] is typically the module namespace name, don't match
	-- that!
        if k ~= 1 and from[k] ~= M[k] then print (k) end
      end
    ]])

  elseif from and enhanced_in then
    return tabulate_output ([[
      local from = ]] .. from .. [[
      local M = require "]] .. enhanced_in .. [["

      for k, v in pairs (M) do
        if from[k] ~= M[k] and from[k] ~= nil then print (k) end
      end
    ]])

  elseif from and enhanced_after then
    return tabulate_output ([[
      local before, after = {}, {}
      local from = ]] .. from .. [[

      for k, v in pairs (from) do before[k] = v end
      ]] .. enhanced_after .. [[
      for k, v in pairs (from) do after[k] = v end

      for k, v in pairs (before) do
        if after[k] ~= nil and after[k] ~= v then print (k) end
      end
    ]])
  end

  assert (false, "missing argument to show_apis")
end


-- Not local, so that it is available to spec examples.
function totable (x)
  local _, m = pcall (function (x) return getmetatable (x)["__totable"] end, x)
  if type (m) == "function" then
    return m (x)
  elseif type (x) == "table" then
    return x
  elseif type (x) == "string" then
    local t = {}
    x:gsub (".", function (c) t[#t + 1] = c end)
    return t
  else
    return nil
  end
end


-- Stub inprocess.capture if necessary; new in Specl 12.
capture = inprocess.capture or
          function (f, arg) return nil, nil, f (unpack (arg or {})) end



do
  -- Custom matcher for set size and set membership.

  local util     = require "specl.util"
  local matchers = require "specl.matchers"

  local Matcher, matchers, q =
        matchers.Matcher, matchers.matchers, matchers.stringify

  matchers.have_size = Matcher {
    function (self, actual, expect)
      local size = 0
      for _ in pairs (actual) do size = size + 1 end
      return size == expect
    end,

    actual = "table",

    format_expect = function (self, expect)
      return " a table containing " .. expect .. " elements, "
    end,

    format_any_of = function (self, alternatives)
      return " a table with any of " ..
             util.concat (alternatives, util.QUOTED) .. " elements, "
    end,
  }

  matchers.have_member = Matcher {
    function (self, actual, expect)
      return actual[expect] ~= nil
    end,

    actual = "set",

    format_expect = function (self, expect)
      return " a set containing " .. q (expect) .. ", "
    end,

    format_any_of = function (self, alternatives)
      return " a set containing any of " ..
             util.concat (alternatives, util.QUOTED) .. ", "
    end,
  }

  -- Alias that doesn't tickle sc_error_message_uppercase.
  matchers.raise = matchers.error
end