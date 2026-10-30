local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

vim.cmd("runtime plugin/mo-markdown-preview.lua")

local config = require("mo-markdown-preview.config")
local preview = require("mo-markdown-preview")

local fake_mo = root .. "/tests/fake_mo.sh"
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local fake_log = tmp .. "/mo.log"
vim.env.MO_FAKE_LOG = fake_log

local opened = nil
local notified = {}
local original_notify = vim.notify
vim.notify = function(message, level)
  table.insert(notified, { message = message, level = level })
end

local total = 0
local failed = 0

local function check(condition, message)
  if not condition then
    error(message or "check failed", 2)
  end
end

local function eq(actual, expected, message)
  if actual ~= expected then
    local detail = string.format(
      "%s\nexpected: %s\nactual:   %s",
      message or "values differ",
      vim.inspect(expected),
      vim.inspect(actual)
    )
    error(detail, 2)
  end
end

local function contains(haystack, needle, message)
  check(type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil, message or ("missing: " .. needle))
end

local function write_file(path, content)
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function reset_log()
  local file = assert(io.open(fake_log, "w"))
  file:close()
end

local function log_text()
  return read_file(fake_log) or ""
end

local function log_args()
  return vim.split(log_text(), "\n", { plain = true, trimempty = true })
end

local function last_arg()
  local args = log_args()
  return args[#args]
end

local function has_arg(value)
  for _, arg in ipairs(log_args()) do
    if arg == value then
      return true
    end
  end
  return false
end

local function wait_for(predicate, message)
  if not vim.wait(5000, predicate, 20) then
    error(message or "timed out", 2)
  end
end

local function notified_text()
  local parts = {}
  for _, item in ipairs(notified) do
    table.insert(parts, tostring(item.message))
  end
  return table.concat(parts, "\n")
end

local function open_buffer(path, content, filetype)
  write_file(path, content)
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = filetype or "markdown"
  return vim.api.nvim_get_current_buf()
end

local function setup(extra)
  config.reset()
  opened = nil
  notified = {}

  local opts = {
    cmd = fake_mo,
    port = 6123,
    target = "nvim-test",
    browser_func = function(url)
      opened = url
    end,
  }
  for key, value in pairs(extra or {}) do
    opts[key] = value
  end

  preview.setup(opts)
  reset_log()
end

local function reset_state()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
  vim.wait(20)
  pcall(vim.cmd, "enew")
end

local function test(name, fn)
  total = total + 1
  reset_state()
  setup()
  vim.env.MO_FAKE_FAIL = ""
  vim.env.MO_FAKE_MULTI = ""

  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    print(string.format("ok %d - %s", total, name))
  else
    failed = failed + 1
    print(string.format("not ok %d - %s", total, name))
    print("  " .. tostring(err):gsub("\n", "\n  "))
  end
end

test("registers the :MoPreview command", function()
  eq(vim.fn.exists(":MoPreview"), 2)
end)

test("passes the current file to mo", function()
  local path = tmp .. "/README.md"
  open_buffer(path, "# Hello\n")

  vim.cmd("MoPreview")
  wait_for(function()
    return opened ~= nil
  end, "browser was not opened")

  eq(opened, "http://localhost:6275/?file=fake")
  eq(last_arg(), path)
  check(has_arg("--no-open"))
  check(has_arg("--json"))
  check(has_arg("--port"))
  check(has_arg("6123"))
  check(has_arg("--target"))
  check(has_arg("nvim-test"))
end)

test("does not sync modified buffer contents", function()
  local path = tmp .. "/modified.md"
  local bufnr = open_buffer(path, "# Original\n")
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, { "", "unsaved line" })
  check(vim.bo[bufnr].modified, "buffer should be modified")

  check(preview.preview(), "preview should start")
  wait_for(function()
    return opened ~= nil
  end, "browser was not opened")

  eq(last_arg(), path, "mo should receive the file on disk, not a snapshot")
  eq(read_file(path), "# Original\n", "the original file must not be modified")
  check(vim.bo[bufnr].modified, "the buffer should still be modified")
  eq(#vim.fn.glob(tmp .. "/.mo-markdown-preview-*", false, true), 0, "no snapshot files should be created")
end)

test("reports an error for an unnamed buffer", function()
  vim.cmd("enew")
  vim.bo.filetype = "markdown"

  eq(preview.preview(), false, "preview should fail")
  contains(notified_text(), "no file name")
  eq(log_text(), "", "mo must not run without a file")
end)

test("reports an error for a buffer with no file on disk", function()
  local path = tmp .. "/missing.md"
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = "markdown"
  check(vim.fn.filereadable(path) == 0, "the test file should not exist")

  eq(preview.preview(), false, "preview should fail")
  contains(notified_text(), "not backed by a readable file")
  eq(log_text(), "", "mo must not run without a file")
end)

test("reports an error for an invalid buffer", function()
  eq(preview.preview({ bufnr = 999999 }), false, "preview should fail")
  contains(notified_text(), "invalid buffer")
end)

test("finds the exact file when mo returns several files", function()
  vim.env.MO_FAKE_MULTI = "1"
  local path = tmp .. "/multi.md"
  open_buffer(path, "# Multi\n")

  check(preview.preview(), "preview should start")
  wait_for(function()
    return opened ~= nil
  end, "browser was not opened")

  eq(opened, "http://localhost:6275/?file=match")
end)

test("rejects unsupported filetypes unless forced", function()
  local path = tmp .. "/notes.txt"
  open_buffer(path, "plain text\n", "text")

  eq(preview.preview(), false, "unsupported filetype should be rejected")
  contains(notified_text(), "not enabled")
  eq(log_text(), "", "mo must not run for a rejected buffer")

  vim.cmd("MoPreview!")
  wait_for(function()
    return opened ~= nil
  end, "forced preview should start")
  eq(last_arg(), path)
end)

test("can show the URL without opening a browser", function()
  setup({ open_browser = false })
  local path = tmp .. "/no-browser.md"
  open_buffer(path, "# No browser\n")

  check(preview.preview(), "preview should start")
  wait_for(function()
    return notified_text():find("preview: http://localhost:6275", 1, true) ~= nil
  end, "preview URL was not reported")
  check(opened == nil, "browser_func must not run when open_browser is false")
end)

test("reports a failing mo invocation and can retry", function()
  local path = tmp .. "/failure.md"
  open_buffer(path, "# Failure\n")

  vim.env.MO_FAKE_FAIL = "1"
  check(preview.preview(), "preview should start")
  wait_for(function()
    return notified_text():find("fake mo failure", 1, true) ~= nil
  end, "mo's error was not reported")
  check(opened == nil, "browser must not open after a failure")

  vim.env.MO_FAKE_FAIL = ""
  opened = nil
  reset_log()
  check(preview.preview(), "retry should start")
  wait_for(function()
    return opened ~= nil
  end, "retry did not open the browser")
end)

test("reports a missing mo executable", function()
  setup({ cmd = tmp .. "/does-not-exist" })
  local path = tmp .. "/missing-mo.md"
  open_buffer(path, "# Missing mo\n")

  eq(preview.preview(), false, "preview should fail synchronously")
  wait_for(function()
    return notified_text():find("could not find", 1, true) ~= nil
  end, "missing executable was not reported")
  check(opened == nil, "browser must not open")
end)

test("validates configuration", function()
  check(not pcall(preview.setup, { cmd = "" }), "cmd must not be empty")
  check(not pcall(preview.setup, { port = 0 }), "port 0 should be rejected")
  check(not pcall(preview.setup, { filetypes = "markdown" }), "filetypes must be a table")
  check(not pcall(preview.setup, { target = 123 }), "target must be a string or nil")
  check(not pcall(preview.setup, { open_browser = "yes" }), "open_browser must be a boolean")
end)

vim.notify = original_notify
vim.fn.delete(tmp, "rf")

print(string.format("%d tests, %d failures", total, failed))
if failed > 0 then
  os.exit(1)
end
os.exit(0)
