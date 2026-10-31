local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

vim.cmd("runtime plugin/mo-markdown-preview.lua")

local config = require("mo-markdown-preview.config")
local cli = require("mo-markdown-preview.cli")
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
local original_ui_open = vim.ui.open
vim.ui.open = function(url)
  opened = url
  return {}
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

local function target_arg(cmd)
  for i, arg in ipairs(cmd) do
    if arg == "--target" then
      return cmd[i + 1]
    end
  end
  return nil
end

local function logged_target()
  return target_arg(log_args())
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

local function open_buffer(path, content)
  write_file(path, content)
  vim.cmd.edit(vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

local function setup(extra)
  config.reset()
  opened = nil
  notified = {}

  local opts = {
    cmd = fake_mo,
    port = 6123,
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

test("parses --target, --port, --no-open, and --open", function()
  local args = require("mo-markdown-preview.args")

  local parsed, err = args.parse("")
  eq(err, nil)
  eq(next(parsed), nil, "no arguments should produce empty options")

  parsed = assert(args.parse("--target docs --port 6276 --no-open"))
  eq(parsed.target, "docs")
  eq(parsed.port, 6276)
  eq(parsed.open, false)

  eq(assert(args.parse("--target=docs")).target, "docs")
  eq(assert(args.parse("--port=6276")).port, 6276)
  eq(assert(args.parse([[--target "my group"]])).target, "my group")
  eq(assert(args.parse([[--target="my group"]])).target, "my group")
  eq(assert(args.parse([[--target='my group']])).target, "my group")
  eq(assert(args.parse("--no-open")).open, false)
  eq(assert(args.parse("--open")).open, true)
  eq(assert(args.parse("--no-open --open")).open, true)
  eq(assert(args.parse("--open --no-open")).open, false)

  local cases = {
    { "--target", "--target" },
    { "--port", "--port" },
    { "--port nope", "invalid --port" },
    { "--port 0", "invalid --port" },
    { "--port 65536", "invalid --port" },
    { "--no-open=1", "--no-open" },
    { "--open=1", "--open" },
    { "--bogus", "unknown option" },
    { "docs", "use --target" },
    { [[--target "unterminated]], "unterminated quote" },
  }
  for _, case in ipairs(cases) do
    local value, case_err = args.parse(case[1])
    eq(value, nil, "should reject: " .. case[1])
    contains(case_err, case[2])
  end
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
  local expected_target = target_arg(cli.command(path, config.get(), nil))
  check(expected_target ~= nil, "default target should be present")
  eq(logged_target(), expected_target)
end)

test("accepts an explicit target argument", function()
  local path = tmp .. "/grouped.md"
  open_buffer(path, "# Grouped\n")

  vim.cmd("MoPreview --target docs")
  wait_for(function()
    return opened ~= nil
  end, "browser was not opened")

  eq(logged_target(), "docs")
  local default_target = target_arg(cli.command(path, config.get(), nil))
  check(default_target ~= nil, "default target should be present")
  check(default_target ~= "docs", "default target should differ from the explicit target")
end)

test("applies --port and --no-open to one call", function()
  local path = tmp .. "/flags.md"
  open_buffer(path, "# Flags\n")

  vim.cmd("MoPreview --port 6200 --no-open")
  wait_for(function()
    return notified_text():find("http://localhost:6275", 1, true) ~= nil
  end, "preview URL was not reported")

  check(has_arg("6200"), "--port value should be passed to mo")
  check(has_arg("--no-open"), "mo should still run with --no-open")
  eq(opened, nil, "browser must not open with --no-open")
  eq(config.get().port, 6123, "--port must not change the configuration")
  eq(config.get().open, true, "--no-open must not change the configuration")
end)

test("uses the configured target when --target is omitted", function()
  setup({ target = "shared" })
  local path = tmp .. "/configured-target.md"
  open_buffer(path, "# Configured target\n")

  vim.cmd("MoPreview")
  wait_for(function()
    return opened ~= nil
  end, "browser was not opened")

  eq(config.get().target, "shared")
  eq(logged_target(), "shared", "configured target should be passed to mo")
  local default_target = target_arg(cli.command(path, config.get(), nil))
  check(default_target ~= nil, "default target should be present")
  check(default_target ~= "shared", "built-in target should differ from the configured target")
end)

test("--target overrides the configured target", function()
  setup({ target = "shared" })
  local path = tmp .. "/target-override.md"
  open_buffer(path, "# Target override\n")

  vim.cmd("MoPreview --target docs")
  wait_for(function()
    return opened ~= nil
  end, "browser was not opened")

  eq(logged_target(), "docs", "--target should override the configured target")
  eq(config.get().target, "shared")
end)

test("accepts a quoted target value", function()
  local path = tmp .. "/quoted.md"
  open_buffer(path, "# Quoted\n")

  vim.cmd([[MoPreview --target="my group" --no-open]])
  wait_for(function()
    return notified_text():find("http://localhost:6275", 1, true) ~= nil
  end, "preview URL was not reported")

  check(has_arg("my group"), "quoted target should reach mo as one argument")
end)

test("--open overrides open = false", function()
  setup({ open = false })
  local path = tmp .. "/force-open.md"
  open_buffer(path, "# Force open\n")

  vim.cmd("MoPreview --open")
  wait_for(function()
    return opened ~= nil
  end, "browser was not opened")

  eq(config.get().open, false, "--open must not change the configuration")
end)

test("rejects invalid command arguments before running mo", function()
  local path = tmp .. "/bad-args.md"
  open_buffer(path, "# Bad args\n")

  vim.cmd("MoPreview --port nope")
  contains(notified_text(), "invalid --port")

  notified = {}
  vim.cmd("MoPreview --unknown")
  contains(notified_text(), "unknown option")

  notified = {}
  vim.cmd("MoPreview docs")
  contains(notified_text(), "use --target")

  eq(log_text(), "", "mo must not run for invalid arguments")
end)

test("uses the full file path as the default target", function()
  local cfg = config.get()
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local home = vim.fs.normalize(vim.fn.expand("~"))
  local outside = vim.fn.has("win32") == 1 and "C:/mo-preview-outside.md" or "/mo-preview-outside.md"

  local function expected(path)
    return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  end

  eq(target_arg(cli.command(cwd .. "/README.md", cfg, nil)), expected(cwd .. "/README.md"))
  eq(target_arg(cli.command(cwd .. "/docs/README.md", cfg, nil)), expected(cwd .. "/docs/README.md"))
  eq(target_arg(cli.command(home .. "/.config/test.md", cfg, nil)), expected(home .. "/.config/test.md"))
  eq(target_arg(cli.command(outside, cfg, nil)), expected(outside))
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

  eq(preview.preview(), false, "preview should fail")
  contains(notified_text(), "no file name")
  eq(log_text(), "", "mo must not run without a file")
end)

test("reports an error for a buffer with no file on disk", function()
  local path = tmp .. "/missing.md"
  vim.cmd.edit(vim.fn.fnameescape(path))
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

test("does not check the buffer filetype", function()
  local path = tmp .. "/notes.txt"
  open_buffer(path, "plain text\n")
  vim.bo.filetype = "text"

  check(preview.preview(), "preview should start for any filetype")
  wait_for(function()
    return opened ~= nil
  end, "browser was not opened")
  eq(last_arg(), path)
end)

test("can show the URL without opening a browser", function()
  setup({ open = false })
  local path = tmp .. "/no-browser.md"
  open_buffer(path, "# No browser\n")

  check(preview.preview(), "preview should start")
  wait_for(function()
    return notified_text():find('preview "http://localhost:6275', 1, true) ~= nil
  end, "preview URL was not reported")
  check(opened == nil, "vim.ui.open must not run when open is false")
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

test("reports invalid configuration without applying it", function()
  local before = config.get()

  local function expect_invalid(opts, field)
    notified = {}
    local after = preview.setup(opts)
    contains(notified_text(), field)
    eq(notified[1].level, vim.log.levels.ERROR)
    eq(after, before)
  end

  expect_invalid({ cmd = "" }, "cmd")
  expect_invalid({ target = 1 }, "target")
  expect_invalid({ port = 0 }, "port")
  expect_invalid({ open = "yes" }, "open")
end)

vim.notify = original_notify
vim.ui.open = original_ui_open
vim.fn.delete(tmp, "rf")

print(string.format("%d tests, %d failures", total, failed))
if failed > 0 then
  os.exit(1)
end
os.exit(0)
