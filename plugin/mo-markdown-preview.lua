if vim.g.loaded_mo_markdown_preview == 1 then
  return
end
vim.g.loaded_mo_markdown_preview = 1

local usage = ":MoPreview [--target TARGET] [--port PORT] [--no-open|--open]"

vim.api.nvim_create_user_command("MoPreview", function(opts)
  local args = require("mo-markdown-preview.args")
  local parsed, err = args.parse(opts.args)
  if not parsed then
    require("mo-markdown-preview.util").notify(
      string.format("%s\nusage: %s", err, usage),
      vim.log.levels.ERROR
    )
    return
  end

  require("mo-markdown-preview").preview(parsed)
end, {
  nargs = "*",
  desc = "Preview the current buffer with mo",
  complete = function(arg_lead)
    local matches = {}
    for _, flag in ipairs({ "--target", "--port", "--no-open", "--open" }) do
      if vim.startswith(flag, arg_lead) then
        matches[#matches + 1] = flag
      end
    end
    return matches
  end,
})
