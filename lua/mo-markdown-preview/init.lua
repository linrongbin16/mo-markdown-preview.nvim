local config = require("mo-markdown-preview.config")
local cli = require("mo-markdown-preview.cli")
local opener = require("mo-markdown-preview.open")
local util = require("mo-markdown-preview.util")

local M = {}

local function supported(bufnr, force)
	if force then
		return true
	end

	local cfg = config.get()
	if #cfg.filetypes == 0 then
		return true
	end

	local filetype = vim.bo[bufnr].filetype
	for _, candidate in ipairs(cfg.filetypes) do
		if candidate == filetype then
			return true
		end
	end

	return false
end

--- Return the file on disk backing a buffer, or nil and an error message.
---@param bufnr integer
---@return string|nil path
---@return string|nil err
local function buffer_file(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return nil, "current buffer has no file name; save it to a file before previewing"
	end
	if vim.fn.filereadable(name) ~= 1 then
		return nil, string.format("current buffer is not backed by a readable file: %s", name)
	end
	return vim.fn.fnamemodify(name, ":p")
end

--- Preview the file backing the current buffer with mo.
---
--- The buffer contents are intentionally not synchronized to mo: mo renders the
--- file on disk and reloads it when Neovim saves the buffer.
---@param opts table|nil
---@return boolean started
function M.preview(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

	if not vim.api.nvim_buf_is_valid(bufnr) then
		util.notify(string.format("invalid buffer %s", vim.inspect(bufnr)), vim.log.levels.ERROR)
		return false
	end

	if not supported(bufnr, opts.force) then
		util.notify(
			string.format(
				"filetype %s is not enabled for preview; use :MoPreview! or add it to `filetypes`",
				vim.inspect(vim.bo[bufnr].filetype)
			),
			vim.log.levels.ERROR
		)
		return false
	end

	local path, path_err = buffer_file(bufnr)
	if not path then
		util.notify(path_err, vim.log.levels.ERROR)
		return false
	end

	local cfg = config.get()
	local target = opts.target
	if target ~= nil and type(target) ~= "string" then
		util.notify("target must be a string or nil", vim.log.levels.ERROR)
		return false
	end
	if target == "" then
		target = nil
	end

	return cli.run(path, cfg, target, function(result)
		if not result or result.code ~= 0 then
			local code = result and result.code or -1
			local output = "no error output"
			if result then
				if type(result.stderr) == "string" and result.stderr ~= "" then
					output = result.stderr
				elseif type(result.stdout) == "string" and result.stdout ~= "" then
					output = result.stdout
				end
			end
			util.notify(
				string.format("mo exited with code %s: %s", vim.inspect(code), util.trim(output)),
				vim.log.levels.ERROR
			)
			return
		end

		local data, decode_err = cli.decode(result.stdout)
		if not data then
			util.notify(decode_err, vim.log.levels.ERROR)
			return
		end

		local url = cli.find_url(data, path)
		if not url then
			util.notify(
				string.format("mo did not return a preview URL for %s", vim.inspect(path)),
				vim.log.levels.ERROR
			)
			return
		end

		local opened, open_err = opener.open(url, cfg)
		if not opened then
			util.notify(
				string.format(
					"preview ready at %s (could not open browser: %s)",
					vim.inspect(url),
					vim.inspect(open_err)
				),
				vim.log.levels.WARN
			)
		elseif not cfg.open_browser then
			util.notify(string.format("preview %s", vim.inspect(url)))
		end
	end)
end

--- Update the plugin configuration.
---@param opts table|nil
---@return table
function M.setup(opts)
	return config.setup(opts)
end

return M
