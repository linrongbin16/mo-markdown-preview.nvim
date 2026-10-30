local M = {}

local function fallback_command(url)
  if vim.fn.has("win32") == 1 then
    return { "rundll32", "url.dll,FileProtocolHandler", url }
  end

  if vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then
    return { "open", url }
  end

  if vim.fn.has("wsl") == 1 then
    if vim.fn.executable("wslview") == 1 then
      return { "wslview", url }
    end
    if vim.fn.executable("cmd.exe") == 1 then
      return { "cmd.exe", "/c", "start", "", url }
    end
  end

  if vim.fn.executable("xdg-open") == 1 then
    return { "xdg-open", url }
  end
  if vim.fn.executable("open") == 1 then
    return { "open", url }
  end

  return nil
end

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

  local ui_err
  if vim.ui and vim.ui.open then
    local ok, proc, err = pcall(vim.ui.open, url)
    if ok and proc ~= nil then
      return true
    end
    ui_err = ok and err or tostring(proc)
  end

  local cmd = fallback_command(url)
  if not cmd then
    return false, ui_err or "no URL opener found; set browser_func or open_browser = false"
  end

  local ok, job = pcall(vim.fn.jobstart, cmd, { detach = true })
  if ok and job > 0 then
    return true
  end

  return false, "failed to launch " .. cmd[1]
end

return M
