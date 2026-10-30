local util = require("mo-markdown-preview.util")

local M = {}

M.defaults = {
  -- Command used to talk to mo. Can be an absolute path or a name on $PATH.
  cmd = "mo",

  -- mo group (--target). nil means mo's "default" group.
  target = nil,

  -- mo server port. nil means mo's default (6275).
  port = nil,

  -- Buffer filetypes accepted by :MoPreview. An empty table allows every
  -- filetype. :MoPreview! always bypasses this check.
  filetypes = { "markdown", "markdown.mdx", "mdx" },

  -- Open the preview URL with the default browser.
  open_browser = true,

  -- Optional function(url) used instead of the default browser opener.
  browser_func = nil,
}

local current = vim.deepcopy(M.defaults)

local function invalid(name, expected)
  util.notify(string.format("mo-markdown-preview: '%s' must be %s", name, expected), vim.log.levels.ERROR)
  return false
end

local function validate(opts)
  if opts.cmd ~= nil and (type(opts.cmd) ~= "string" or opts.cmd == "") then
    return invalid("cmd", "a non-empty string")
  end

  if opts.target ~= nil and (type(opts.target) ~= "string" or opts.target == "") then
    return invalid("target", "a non-empty string or nil")
  end

  if
    opts.port ~= nil
    and (
      type(opts.port) ~= "number"
      or opts.port % 1 ~= 0
      or opts.port < 1
      or opts.port > 65535
    )
  then
    return invalid("port", "an integer between 1 and 65535, or nil")
  end

  if opts.filetypes ~= nil then
    if type(opts.filetypes) ~= "table" then
      return invalid("filetypes", "a table of filetype strings")
    end
    for _, filetype in ipairs(opts.filetypes) do
      if type(filetype) ~= "string" or filetype == "" then
        return invalid("filetypes", "a table of non-empty filetype strings")
      end
    end
  end

  if opts.open_browser ~= nil and type(opts.open_browser) ~= "boolean" then
    return invalid("open_browser", "a boolean")
  end

  if opts.browser_func ~= nil and type(opts.browser_func) ~= "function" then
    return invalid("browser_func", "a function or nil")
  end

  return true
end

--- Update the plugin configuration.
---@param opts table|nil
---@return table
function M.setup(opts)
  opts = opts or {}
  if not validate(opts) then
    return current
  end
  -- A shallow merge is intentional: options such as `filetypes` are lists and
  -- should be replaced wholesale instead of being merged index by index.
  current = vim.tbl_extend("force", vim.deepcopy(M.defaults), opts)
  return current
end

---@return table
function M.get()
  return current
end

--- Restore defaults. Mostly useful for tests.
---@return table
function M.reset()
  current = vim.deepcopy(M.defaults)
  return current
end

return M
