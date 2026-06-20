local M = {}

M.header_height = 4

function M.menu(opts)
  local available = math.max(40, vim.o.columns - 4)
  local inner_available = math.max(1, available - 3)
  local preview_width = math.min(opts.preview_width, math.max(24, math.floor(inner_available * 0.46)))
  local list_width = math.min(opts.width, math.max(32, inner_available - preview_width))
  if list_width + preview_width > inner_available then
    list_width = math.max(1, math.floor(inner_available * 0.55))
    preview_width = math.max(1, inner_available - list_width)
  end
  local total_screen_width = list_width + preview_width + 3
  local header_width = total_screen_width - 2
  local available_height = math.max(8, vim.o.lines - 6)
  local pane_height = math.max(
    1,
    math.min(math.max(1, available_height - (M.header_height + 3)), math.max(6, opts.height))
  )
  local total_screen_height = M.header_height + pane_height + 3
  return {
    list_width = list_width,
    preview_width = preview_width,
    header_width = header_width,
    total_width = total_screen_width,
    total_height = total_screen_height,
    pane_height = pane_height,
  }
end

return M
