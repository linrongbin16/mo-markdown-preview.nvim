local util = require("mo-markdown-preview.util")

local M = {}

M.defaults = {
	-- Command used to talk to mo. Can be an absolute path or a name on $PATH.
	cmd = "mo",

	-- Default mo group. nil uses the built-in per-file group.
	target = nil,

	-- mo server port. nil means mo's default (6275).
	port = nil,

	-- Open the preview URL with the default browser.
	open = true,
}

local current = vim.deepcopy(M.defaults)

local function invalid(name, expected)
	util.notify(string.format("%s must be %s", vim.inspect(name), expected), vim.log.levels.ERROR)
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
		opts.port ~= nil and (type(opts.port) ~= "number" or opts.port % 1 ~= 0 or opts.port < 1 or opts.port > 65535)
	then
		return invalid("port", "an integer between 1 and 65535, or nil")
	end

	if opts.open ~= nil and type(opts.open) ~= "boolean" then
		return invalid("open", "a boolean")
	end

	return true
end

--- Update the plugin configuration.
---
--- The returned table is a copy, so callers cannot mutate the configuration
--- through it.
---@param opts table|nil
---@return table
function M.setup(opts)
	opts = opts or {}
	if not validate(opts) then
		return M.get()
	end
	-- A shallow merge is intentional: option values are replaced wholesale
	-- instead of being merged key by key.
	current = vim.tbl_extend("force", vim.deepcopy(M.defaults), opts)
	return M.get()
end

--- Return a copy of the current configuration.
---
--- The configuration table is internal state: handing out the table itself
--- would let any caller (another plugin, a user config, a test) change the
--- plugin's behaviour by mutating it. Callers who need to derive a per-call
--- configuration get their own copy to extend.
---@return table
function M.get()
	return vim.deepcopy(current)
end

--- Restore defaults. Mostly useful for tests.
---@return table
function M.reset()
	current = vim.deepcopy(M.defaults)
	return M.get()
end

return M
