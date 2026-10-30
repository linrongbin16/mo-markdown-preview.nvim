local util = require("mo-markdown-preview.util")

local M = {}

local uv = vim.uv or vim.loop

local function executable(cfg)
  local name = vim.fn.expand(cfg.cmd)
  local exe = vim.fn.exepath(name)
  if exe == "" or vim.fn.executable(exe) ~= 1 then
    local message = string.format(
      "could not find the 'mo' executable (%s). "
        .. "Install it from https://github.com/k1LoW/mo or set `cmd` in the plugin setup.",
      cfg.cmd
    )
    return nil, message
  end
  return exe
end

local function normalize_path(path)
  local normalized = vim.fn.fnamemodify(path, ":p")

  local ok, real = pcall(uv.fs_realpath, normalized)
  if ok and real then
    normalized = real
  end

  normalized = normalized:gsub("\\", "/")
  if vim.fn.has("win32") == 1 then
    normalized = normalized:lower()
  end
  return normalized
end

--- Build the default group name for a file.
---
--- The group is stable per absolute path and unique across files with the same
--- basename. The 8-character hash mirrors the id mo uses for file entries.
---@param path string
---@return string
local function default_target(path)
  local absolute = vim.fn.fnamemodify(path, ":p")
  local name = vim.fn.fnamemodify(path, ":t")
  return string.format("%s-%s", name, vim.fn.sha256(absolute):sub(1, 8))
end

--- Build the `mo` command used to add a file to the preview server.
---@param path string
---@param cfg table
---@param target string|nil
---@return string[]
function M.command(path, cfg, target)
  local cmd = { cfg.cmd }

  if cfg.port then
    vim.list_extend(cmd, { "--port", tostring(cfg.port) })
  end

  local group = target
  if group == nil or group == "" then
    group = default_target(path)
  end
  vim.list_extend(cmd, { "--target", group })

  vim.list_extend(cmd, { "--no-open", "--json", path })
  return cmd
end

--- Decode the JSON document emitted by `mo --json`.
---@param stdout string|nil
---@return table|nil
---@return string|nil
function M.decode(stdout)
  if type(stdout) ~= "string" or stdout:match("^%s*$") then
    return nil, "mo produced no output"
  end

  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok then
    return nil, "could not decode mo's JSON output: " .. util.trim(stdout)
  end
  if type(decoded) ~= "table" then
    return nil, "unexpected mo output: " .. util.trim(stdout)
  end

  return decoded
end

--- Find the deeplink for `path` in the JSON returned by `mo --json`.
---@param data table
---@param path string
---@return string|nil
function M.find_url(data, path)
  local wanted = normalize_path(path)
  local files = type(data.files) == "table" and data.files or {}

  for _, file in ipairs(files) do
    if type(file) == "table" and type(file.url) == "string" and type(file.path) == "string" then
      if normalize_path(file.path) == wanted then
        return file.url
      end
    end
  end

  -- Some older/simpler mo invocations only return one file. Accept it when
  -- there is no ambiguity.
  if #files == 1 and type(files[1]) == "table" and type(files[1].url) == "string" then
    return files[1].url
  end

  -- If mo returned no files at all, the group URL is still a useful fallback.
  -- Never fall back to it when other files were returned: opening a different
  -- file would be worse than reporting an error.
  if #files == 0 and type(data.url) == "string" and data.url ~= "" then
    return data.url
  end

  return nil
end

--- Run mo to add a file and return its preview URL through `callback`.
---@param path string
---@param cfg table
---@param target string|nil
---@param callback fun(result: table)
---@return boolean started
function M.run(path, cfg, target, callback)
  local exe, err = executable(cfg)
  if not exe then
    vim.schedule(function()
      callback({
        code = -1,
        stdout = "",
        stderr = err,
      })
    end)
    return false
  end

  local cmd = M.command(path, cfg, target)
  cmd[1] = exe

  local ok, proc = pcall(vim.system, cmd, {
    text = true,
    timeout = 30000,
    cwd = vim.fn.getcwd(),
  }, function(obj)
    vim.schedule(function()
      callback(obj)
    end)
  end)

  if not ok then
    vim.schedule(function()
      callback({
        code = -1,
        stdout = "",
        stderr = tostring(proc),
      })
    end)
  end

  return ok
end

return M
