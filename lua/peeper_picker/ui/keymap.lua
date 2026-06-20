local M = {}

function M.bind(buf, modes, lhs, fn)
  vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, silent = true })
end

return M
