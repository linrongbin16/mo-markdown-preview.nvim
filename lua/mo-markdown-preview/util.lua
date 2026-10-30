local M = {}

--- Show a notification with the plugin title.
---@param message string
---@param level integer|nil
function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "mo-markdown-preview" })
end

--- Trim surrounding whitespace and truncate long command output.
---@param value any
---@return string
function M.trim(value)
  if type(value) ~= "string" then
    return ""
  end
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  if #value > 1200 then
    value = value:sub(1, 1200) .. "..."
  end
  return value
end

return M
