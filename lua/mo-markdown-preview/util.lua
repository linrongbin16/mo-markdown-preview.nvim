local M = {}

--- Show a notification with the plugin title.
---@param message string
---@param level integer|nil
function M.notify(message, level)
  message = string.format("mo-markdown-preview: %s", message)
  level = level or vim.log.levels.INFO
  vim.notify(message, level)
end

--- Trim surrounding whitespace and truncate long command output.
---@param value any
---@return string
function M.trim(value)
  if type(value) ~= "string" then
    return ""
  end
  local max_len = 120
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  if #value > max_len then
    value = value:sub(1, max_len) .. "..."
  end
  return value
end

return M
