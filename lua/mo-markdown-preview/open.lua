local M = {}

--- Open a URL in the user's browser.
---
--- `opts` is the plugin configuration. A custom `browser_func` always wins.
--- Setting `open_browser = false` makes this a no-op so the caller can show
--- the URL instead (useful over SSH or in headless environments).
---@param url string
---@param opts table
---@return boolean ok
---@return string|nil err
function M.open(url, opts)
  if opts.open_browser == false then
    return true
  end

  if opts.browser_func then
    local ok, err = pcall(opts.browser_func, url)
    if not ok then
      return false, tostring(err)
    end
    return true
  end

  if not vim.ui.open then
    return false, "vim.ui.open is not available"
  end

  local ok, proc, err = pcall(vim.ui.open, url)
  if not ok then
    return false, tostring(proc)
  end
  if proc ~= nil then
    return true
  end

  return false, err or "could not open URL"
end

return M
