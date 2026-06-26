local M = {}

M.defaults = {
  width = 92,
  height = 18,
  preview_width = 86,
  preview_context = 5,
  border = "single",
  title = " peeper-picker.nvim ",
  jump = "tabedit",
  reuse_window = true,
  expanded_match_limit = 50000,
  scan_files_per_tick = 64,
  classify_files_per_tick = 8,
  default_result_filtering = "all",
  default_keymaps = {
    enabled = false,
    find = "<leader>pp",
  },
  ignored_dirs = {},
  ignored_keywords = {},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
