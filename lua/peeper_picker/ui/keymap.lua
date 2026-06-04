local M = {}

-- Buffer-local keymap helper used by the menu and filter panel.
function M.bind(buf, modes, lhs, fn)
  vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, silent = true })
end

return M
