if vim.g.loaded_mo_markdown_preview == 1 then
  return
end
vim.g.loaded_mo_markdown_preview = 1

local open_usage = ":MoOpen [--target TARGET] [--port PORT] [--no-open|--open]"
local close_usage = ":MoClose [--target TARGET] [--port PORT]"

local function complete(flags)
  return function(arg_lead)
    local matches = {}
    for _, flag in ipairs(flags) do
      if vim.startswith(flag, arg_lead) then
        matches[#matches + 1] = flag
      end
    end
    return matches
  end
end

local function parse(opts, usage, parse_opts)
  local args = require("mo-markdown-preview.args")
  local parsed, err = args.parse(opts.args, parse_opts)
  if not parsed then
    require("mo-markdown-preview.util").notify(
      string.format("%s\nusage: %s", err, usage),
      vim.log.levels.ERROR
    )
    return nil
  end
  return parsed
end

vim.api.nvim_create_user_command("MoOpen", function(opts)
  local parsed = parse(opts, open_usage)
  if not parsed then
    return
  end
  require("mo-markdown-preview").open(parsed)
end, {
  nargs = "*",
  desc = "Open the current buffer with mo",
  complete = complete({ "--target", "--port", "--no-open", "--open" }),
})

vim.api.nvim_create_user_command("MoClose", function(opts)
  local parsed = parse(opts, close_usage, { allow_open = false })
  if not parsed then
    return
  end
  require("mo-markdown-preview").close(parsed)
end, {
  nargs = "*",
  desc = "Close the current buffer's file in mo",
  complete = complete({ "--target", "--port" }),
})
