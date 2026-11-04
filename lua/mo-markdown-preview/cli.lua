local util = require("mo-markdown-preview.util")

local M = {}

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

--- Normalize a path so two spellings of the same file compare equal.
---
--- This must mirror what mo does to the paths it reports, so the deeplink
--- lookup can match them. mo resolves the argument with Go's `filepath.Abs`,
--- which is purely lexical: it makes the path absolute and collapses `.`, `..`
--- and repeated separators, but it does **not** resolve symlinks. Resolving
--- them here (for example with `uv.fs_realpath`) would make a symlinked file
--- never match the path mo returns, and when several files come back the
--- lookup would fall back to the wrong deeplink.
---@param path string
---@return string
local function normalize_path(path)
  local normalized = vim.fn.fnamemodify(path, ":p")
  normalized = vim.fs.normalize(normalized)
  normalized = normalized:gsub("\\", "/")
  if vim.fn.has("win32") == 1 then
    normalized = normalized:lower()
  end
  return normalized
end

--- Build the default group name for a file.
---
--- The full path is URI-encoded with Neovim's RFC 3986 encoder, which keeps
--- URL-path characters (including sub-delims) and percent-encodes the rest.
--- Escapes are uppercased to keep the URL canonical. Percent-encoding is
--- injective, so distinct files always get distinct group names.
---@param path string
---@return string
local function default_target(path)
  local absolute = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  local encoded = vim.uri_encode(absolute, "rfc3986")
  return (encoded:gsub("%%(%x%x)", function(hex)
    return "%" .. hex:upper()
  end))
end

--- Build a mo command with the shared port/target flags.
---@param path string
---@param cfg table
---@param target string|nil
---@param flags string[]
---@return string[]
local function build_command(path, cfg, target, flags)
  local cmd = { cfg.cmd }

  if cfg.port then
    vim.list_extend(cmd, { "--port", tostring(cfg.port) })
  end

  local group = target
  if group == nil or group == "" then
    group = default_target(path)
  end
  vim.list_extend(cmd, { "--target", group })
  vim.list_extend(cmd, flags)
  vim.list_extend(cmd, { path })
  return cmd
end

--- Build the `mo` command used to add a file to the preview server, or to
--- close it again.
---
--- mo always runs with `--no-open`: the plugin opens the file's deeplink
--- itself, so `--open` is never passed and a single call cannot open two tabs.
---@param path string
---@param cfg table
---@param target string|nil
---@param close boolean|nil When true, build the `mo --close` command instead.
---@return string[]
function M.command(path, cfg, target, close)
  local flags = close and { "--close" } or { "--no-open", "--json" }
  return build_command(path, cfg, target, flags)
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
---
--- Only an exact path match is accepted. mo returns the files it actually
--- added, so there is no need to guess: falling back to a lone entry or to the
--- group URL would open a different file (or a different page) whenever the
--- lookup misses. A miss means mo did not add this file, and the caller
--- reports that instead of opening something unrelated.
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

  return nil
end

--- Run a prepared mo command and return its result through `callback`.
---@param cmd string[]
---@param cfg table
---@param callback fun(result: table)
---@return boolean started
local function start(cmd, cfg, callback)
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

--- Run mo to add a file to the preview server, or to close it again, and
--- report the result through `callback`.
---@param path string
---@param cfg table
---@param target string|nil
---@param close boolean|nil When true, run `mo --close`.
---@param callback fun(result: table)
---@return boolean started
function M.run(path, cfg, target, close, callback)
  return start(M.command(path, cfg, target, close), cfg, callback)
end

return M
