local config = require("mo-markdown-preview.config")
local cli = require("mo-markdown-preview.cli")
local opener = require("mo-markdown-preview.open")
local util = require("mo-markdown-preview.util")

local M = {}

--- Return the file on disk backing a buffer, or nil and an error message.
---@param bufnr integer
---@return string|nil path
---@return string|nil err
local function buffer_file(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return nil, "current buffer has no file name; save it to a file first"
	end
	if vim.fn.filereadable(name) ~= 1 then
		return nil, string.format("current buffer is not backed by a readable file: %s", name)
	end
	return vim.fn.fnamemodify(name, ":p")
end

--- Report a failing mo invocation.
---@param result table|nil
local function report_failure(result)
	local code = result and result.code or -1
	local output = "no error output"
	if result then
		if type(result.stderr) == "string" and result.stderr ~= "" then
			output = result.stderr
		elseif type(result.stdout) == "string" and result.stdout ~= "" then
			output = result.stdout
		end
	end
	util.notify(string.format("mo exited with code %s: %s", vim.inspect(code), util.trim(output)), vim.log.levels.ERROR)
end

---@class mo.markdown.preview.Context
---@field path string
---@field target string|nil
---@field call_cfg table

--- Resolve the file, target, and per-call configuration for a command.
---@param opts table
---@param allow_open boolean
---@return mo.markdown.preview.Context|nil
local function resolve(opts, allow_open)
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

	if not vim.api.nvim_buf_is_valid(bufnr) then
		util.notify(string.format("invalid buffer %s", vim.inspect(bufnr)), vim.log.levels.ERROR)
		return nil
	end

	local path, path_err = buffer_file(bufnr)
	if not path then
		util.notify(path_err, vim.log.levels.ERROR)
		return nil
	end

	local cfg = config.get()

	local target = opts.target
	if target ~= nil and type(target) ~= "string" then
		util.notify("target must be a string or nil", vim.log.levels.ERROR)
		return nil
	end
	if target == "" then
		target = nil
	end

	local port = opts.port
	if port ~= nil and (type(port) ~= "number" or port % 1 ~= 0 or port < 1 or port > 65535) then
		util.notify("port must be an integer between 1 and 65535, or nil", vim.log.levels.ERROR)
		return nil
	end

	local open = opts.open
	if open ~= nil and type(open) ~= "boolean" then
		util.notify("open must be a boolean or nil", vim.log.levels.ERROR)
		return nil
	end
	if not allow_open and open ~= nil then
		util.notify("open is not supported by close()", vim.log.levels.ERROR)
		return nil
	end

	local effective_target = target
	if effective_target == nil then
		effective_target = cfg.target
	end
	if effective_target == "" then
		effective_target = nil
	end

	local call_cfg = cfg
	local overrides = nil
	if port ~= nil then
		overrides = { port = port }
	end
	if allow_open and open ~= nil then
		overrides = overrides or {}
		overrides.open = open
	end
	if overrides then
		call_cfg = vim.tbl_extend("force", cfg, overrides)
	end

	return {
		path = path,
		target = effective_target,
		call_cfg = call_cfg,
	}
end

--- Open the file backing the current buffer in mo.
---
--- The buffer contents are intentionally not synchronized to mo: mo renders the
--- file on disk and reloads it when Neovim saves the buffer.
---
--- Per-call options take precedence over the `setup()` configuration:
--- `target` falls back to the configured target, `port` to the configured
--- port, and `open = false` only reports the preview URL. A nil target uses
--- the built-in per-file group.
---@param opts table|nil May contain `bufnr`, `target`, `port`, and `open`.
---@return boolean started
function M.open(opts)
	local ctx = resolve(opts or {}, true)
	if not ctx then
		return false
	end

	return cli.run(ctx.path, ctx.call_cfg, ctx.target, false, function(result)
		if not result or result.code ~= 0 then
			report_failure(result)
			return
		end

		local data, decode_err = cli.decode(result.stdout)
		if not data then
			util.notify(decode_err, vim.log.levels.ERROR)
			return
		end

		local url = cli.find_url(data, ctx.path)
		if not url then
			util.notify(
				string.format("mo did not return a preview URL for %s", vim.inspect(ctx.path)),
				vim.log.levels.ERROR
			)
			return
		end

		local opened, open_err = opener.open(url, ctx.call_cfg)
		if not opened then
			util.notify(
				string.format(
					"preview ready at %s (could not open browser: %s)",
					vim.inspect(url),
					vim.inspect(open_err)
				),
				vim.log.levels.WARN
			)
		elseif not ctx.call_cfg.open then
			util.notify(string.format("preview %s", vim.inspect(url)))
		end
	end)
end

--- Close the file backing the current buffer in mo.
---
--- The target and port must match the ones used to open the file. Per-call
--- options take precedence over the `setup()` configuration: `target` falls
--- back to the configured target and `port` to the configured port.
---@param opts table|nil May contain `bufnr`, `target`, and `port`.
---@return boolean started
function M.close(opts)
	local ctx = resolve(opts or {}, false)
	if not ctx then
		return false
	end

	return cli.run(ctx.path, ctx.call_cfg, ctx.target, true, function(result)
		if not result or result.code ~= 0 then
			report_failure(result)
			return
		end

		util.notify(string.format("closed %s", vim.inspect(ctx.path)))
	end)
end

--- Update the plugin configuration.
---@param opts table|nil
---@return table
function M.setup(opts)
	return config.setup(opts)
end

return M
