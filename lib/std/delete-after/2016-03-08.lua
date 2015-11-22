--[[--
 Provide at least one year of support for deprecated APIs, or at
 least one release cycle if that is longer.

 When `_DEBUG.deprecate` is `true` we don`t even load this support, in
 which case `require`ing this module returns `false`.

 Otherwise, return a table of all functions deprecated in the given
 `RELEASE` and earlier, going back at least one year.  The table is
 keyed on the original module to enable merging deprecated APIs back
 into their previous namespaces - this is handled automatically by the
 documented modules according to the contents of `_DEBUG`.

 In some release after the date of this module, it will be removed and
 these APIs will not be available any longer.
]]


local RELEASE	= "41.2.0"


local M		= false

if not require "std.debug_init"._DEBUG.deprecate then

  local pairs		= pairs
  local type		= type
  local string_format	= string.format

  local _, deprecated	= {
    -- Adding anything else here will probably cause a require loop.
    maturity		= require "std.maturity",
    std			= require "std.base",
    strict		= require "std.strict",
  }

  -- Merge in deprecated APIs from previous release if still available.
  _.ok, deprecated = pcall (require, "std.delete-after.2016-01-31")
  if not _.ok then deprecated = {} end


  local DEPRECATED	= _.maturity.DEPRECATED

  -- Only the above symbols are used below this line.
  local _, _ENV		= nil, _.strict {}


  --[[ ========== ]]--
  --[[ Death Row! ]]--
  --[[ ========== ]]--

  local function toomanyargmsg (name, expect, actual)
    local s = "bad argument #%d to '%s' (no more than %d argument%s expected, got %d)"
    return string_format (s, expect + 1, name, expect, expect == 1 and "" or "s", actual)
  end
 

  -- Ensure deprecated APIs observe _DEBUG warning standards.
  local function X (old, new, fn)
    return DEPRECATED (RELEASE, "'std." .. old .. "'", "use '" .. new .. "' instead", fn)
  end

  local function acyclic_merge (dest, src)
    for k, v in pairs (src) do
      if type (v) == "table" then
        dest[k] = dest[k] or {}
        if type (dest[k]) == "table" then acyclic_merge (dest[k], v) end
      else
        dest[k] = dest[k] or v
      end
    end
    return dest
  end

  M = acyclic_merge ({
    debug = {
      toomanyargmsg = X ("debug.toomanyargmsg", "std.debug.extramsg_toomany", toomanyargmsg),
    },
  },
  deprecated)

end

return M