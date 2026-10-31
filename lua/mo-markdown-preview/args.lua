local M = {}

--- Split a command line into tokens, honoring single and double quotes.
---
--- Quotes may appear in the middle of a token, so `--target="my group"` is one
--- token whose value contains a space.
---@param input string
---@return string[]|nil
---@return string|nil
local function tokenize(input)
	local tokens = {}
	local index = 1
	while index <= #input do
		if input:sub(index, index):match("%s") then
			index = index + 1
		else
			local parts = {}
			local quote = nil
			while index <= #input do
				local char = input:sub(index, index)
				if quote then
					if char == quote then
						quote = nil
					else
						parts[#parts + 1] = char
					end
				elseif char == '"' or char == "'" then
					quote = char
				elseif char:match("%s") then
					break
				else
					parts[#parts + 1] = char
				end
				index = index + 1
			end
			if quote then
				return nil, "unterminated quote in arguments"
			end
			tokens[#tokens + 1] = table.concat(parts)
		end
	end
	return tokens
end

--- Parse the arguments accepted by :MoPreview.
---
--- Supported flags:
---   --target TARGET   mo group name for this call
---   --port PORT       mo server port for this call
---   --no-open         do not open a browser; only report the URL
---   --open            open a browser even when `open = false`
---
--- `--flag=value` is accepted as well. `--no-open` and `--open` override each
--- other, so the last one wins.
---@param input string
---@return table|nil opts
---@return string|nil err
function M.parse(input)
	local tokens, token_err = tokenize(input or "")
	if not tokens then
		return nil, token_err
	end

	local opts = {}
	local index = 1
	while index <= #tokens do
		local token = tokens[index]
		local name, inline = token:match("^(%-%-[%w%-]+)=(.*)$")
		name = name or token

		if name == "--target" then
			local value = inline
			if value == nil then
				index = index + 1
				value = tokens[index]
				if value ~= nil and value:sub(1, 2) == "--" then
					value = nil
				end
			end
			if value == nil or value == "" then
				return nil, "--target requires a non-empty group name"
			end
			opts.target = value
		elseif name == "--port" then
			local value = inline
			if value == nil then
				index = index + 1
				value = tokens[index]
				if value ~= nil and value:sub(1, 2) == "--" then
					value = nil
				end
			end
			if value == nil or value == "" then
				return nil, "--port requires a port number"
			end
			local port = value:match("^%d+$") and tonumber(value)
			if not port or port < 1 or port > 65535 then
				return nil,
					string.format(
						"invalid --port value %s (expected an integer between 1 and 65535)",
						vim.inspect(value)
					)
			end
			opts.port = port
		elseif name == "--no-open" then
			if inline ~= nil then
				return nil, "--no-open does not take a value"
			end
			opts.open = false
		elseif name == "--open" then
			if inline ~= nil then
				return nil, "--open does not take a value"
			end
			opts.open = true
		elseif token:sub(1, 1) == "-" then
			return nil, string.format("unknown option %s", vim.inspect(token))
		else
			return nil,
				string.format(
					"unexpected argument %s; use --target %s (quote values containing spaces)",
					vim.inspect(token),
					vim.inspect(token)
				)
		end

		index = index + 1
	end

	return opts
end

return M
