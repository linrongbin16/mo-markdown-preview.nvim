if vim.g.loaded_mo_markdown_preview == 1 then
  return
end
vim.g.loaded_mo_markdown_preview = 1

vim.api.nvim_create_user_command("MoPreview", function(opts)
  require("mo-markdown-preview").preview({ force = opts.bang })
end, {
  bang = true,
  desc = "Preview the current markdown buffer with mo",
})
