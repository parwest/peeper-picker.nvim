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
  default_keymaps = {
    enabled = false,
    find = "<leader>pp",
  },
  -- Extra directory names to skip during the text-search walk. These are ADDED
  -- to the always-ignored built-in set (.git, node_modules, dist, ...), so the
  -- defaults keep working without any configuration.
  ignored_dirs = {},
  -- Extra cursor words that should not open the picker. Built-in language
  -- keyword fallbacks are always present for common filetypes; this option is
  -- purely additive.
  ignored_keywords = {},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
