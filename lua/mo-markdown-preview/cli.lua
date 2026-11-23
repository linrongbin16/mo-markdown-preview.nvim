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
---
--- A nil `path` builds a port-scoped command: `--clear` works on a whole port,
--- so it takes neither a target group nor a file argument.
---@param path string|nil
---@param cfg table
---@param target string|nil
---@param flags string[]
---@return string[]
local function build_command(path, cfg, target, flags)
  local cmd = { cfg.cmd }

  if cfg.port then
    vim.list_extend(cmd, { "--port", tostring(cfg.port) })
  end

  if path ~= nil then
    local group = target
    if group == nil or group == "" then
      group = default_target(path)
    end
    vim.list_extend(cmd, { "--target", group })
  end

  vim.list_extend(cmd, flags)

  if path ~= nil then
    cmd[#cmd + 1] = path
  end
  return cmd
end

--- Modes accepted by `M.command()` and `M.run()`.
local MODES = {
  open = { "--no-open", "--json" },
  close = { "--close" },
  clear = { "--clear" },
}

--- Build the `mo` command used to add a file to the preview server, to close
--- it again, or to clear a whole port session.
---
--- mo always runs with `--no-open` when opening: the plugin opens the file's
--- deeplink itself, so `--open` is never passed and a single call cannot open
--- two tabs.
---
--- `--clear` is port-scoped, so `path` is nil for it: the command gets only
--- the flags and the optional `--port`.
---@param path string|nil nil for the `clear` mode
---@param cfg table
---@param target string|nil
---@param mode string|boolean|nil "open" (default), "close", or "clear"; `true` is the legacy spelling of "close".
---@return string[]
function M.command(path, cfg, target, mode)
  if mode == true then
    mode = "close"
  elseif mode == false or mode == nil then
    mode = "open"
  end

  local flags = MODES[mode]
  if not flags then
    error(string.format("unknown mo command mode %s", vim.inspect(mode)))
  end
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

--- Read the number of files mo reported adding from its stderr.
---
--- `mo --json` still exits 0 when the server refuses a file: the POST fails,
--- mo skips the entry, and the JSON `files` list comes back empty while stderr
--- says `mo: added 0 item(s) to http://localhost:6275`. That line is the only
--- clue mo leaves about a refused file, so the caller reads it to tell "the
--- server rejected the path" apart from "no file was added at all".
---@param stderr string|nil
---@return integer|nil count nil when mo printed no such line
function M.added_count(stderr)
  if type(stderr) ~= "string" then
    return nil
  end

  local count = stderr:match("added%s+(%d+)%s+item")
  return count and tonumber(count) or nil
end

--- Whether mo would refuse a file as binary.
---
--- mo reads the first 8 KiB of a file and rejects it when the bytes contain a
--- NUL (`readFileHead` and `State.AddFile` in mo's server). Mirroring that
--- check locally lets the plugin name the reason instead of guessing.
---@param path string
---@return boolean
function M.is_binary(path)
  local file = io.open(path, "rb")
  if not file then
    return false
  end

  local head = file:read(8192)
  file:close()
  return type(head) == "string" and head:find("\0", 1, true) ~= nil
end

--- Run a prepared mo command and return its result through `callback`.
---
--- `stdin` is written to the child's standard input. mo reads `os.Stdin` for
--- the `--clear` confirmation, and a nil `stdin` means /dev/null, so the
--- confirmation would see EOF and the call would always be canceled.
---@param cmd string[]
---@param cfg table
---@param callback fun(result: table)
---@param stdin string|nil
---@return boolean started
local function start(cmd, cfg, callback, stdin)
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

  local opts = {
    text = true,
    cwd = vim.fn.getcwd(),
  }
  if stdin ~= nil then
    opts.stdin = stdin
  end

  local ok, proc = pcall(vim.system, cmd, opts, function(obj)
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
---@param path string|nil
---@param cfg table
---@param target string|nil
---@param mode string|boolean|nil "open" (default), "close", or "clear".
---@param callback fun(result: table)
---@return boolean started
function M.run(path, cfg, target, mode, callback)
  return start(M.command(path, cfg, target, mode), cfg, callback)
end

--- Run `mo --clear`, answering its confirmation prompt with `y`.
---
--- mo asks on stderr and reads the answer from stdin; with no stdin the answer
--- is EOF, which mo treats as "canceled". The answer has to be fed here: a
--- Neovim child process never inherits the terminal's stdin, and mo has no
--- non-interactive switch for `--clear`.
---
--- Both a canceled and a successful clear exit 0, so the caller has to inspect
--- stderr instead of the exit code.
---@param cfg table
---@param callback fun(result: table)
---@return boolean started
function M.clear(cfg, callback)
  return start(M.command(nil, cfg, nil, "clear"), cfg, callback, "y\n")
end

return M
