if vim.g.loaded_mo_markdown_preview == 1 then
  return
end
vim.g.loaded_mo_markdown_preview = 1

vim.api.nvim_create_user_command("MoPreview", function(opts)
  local target = vim.trim(opts.args)
  require("mo-markdown-preview").preview({
    force = opts.bang,
    target = target ~= "" and target or nil,
  })
end, {
  bang = true,
  nargs = "?",
  desc = "Preview the current markdown buffer with mo [target]",
})
