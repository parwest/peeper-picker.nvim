local M = {}

M.defaults = {
  width = 92,
  height = 18,
  preview_width = 86,
  preview_height = 14,
  preview_context = 5,
  border = "single",
  title = " peeper-picker.nvim ",
  jump = "tabedit",
  reuse_window = true,
  default_keymaps = {
    enabled = false,
    find = "<leader>pp",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
