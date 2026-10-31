if vim.g.loaded_mo_markdown_preview == 1 then
  return
end
vim.g.loaded_mo_markdown_preview = 1

local preview_usage = ":MoPreview [--target TARGET] [--port PORT] [--close|--no-open|--open]"

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

local function parse(opts, usage)
  local args = require("mo-markdown-preview.args")
  local parsed, err = args.parse(opts.args)
  if not parsed then
    require("mo-markdown-preview.util").notify(
      string.format("%s\nusage: %s", err, usage),
      vim.log.levels.ERROR
    )
    return nil
  end
  return parsed
end

vim.api.nvim_create_user_command("MoPreview", function(opts)
  local parsed = parse(opts, preview_usage)
  if not parsed then
    return
  end
  local preview = require("mo-markdown-preview")
  if parsed.close then
    preview.close(parsed)
  else
    preview.open(parsed)
  end
end, {
  nargs = "*",
  desc = "Open or close the current buffer with mo",
  complete = complete({ "--target", "--port", "--close", "--no-open", "--open" }),
})
