local M = {}

local paths = require("peeper_picker.paths")
local results = require("peeper_picker.results")
local list = require("peeper_picker.ui.list")
local lifecycle = require("peeper_picker.ui.lifecycle")

local function jump_to_item(state, item, command, reuse_window)
  local path = vim.uri_to_fname(item.uri)
  if reuse_window == nil then
    reuse_window = state.opts.reuse_window
  end

  local tabpage, win
  if reuse_window then
    tabpage, win = paths.find_open_window(path)
  end

  if tabpage and win then
    vim.api.nvim_set_current_tabpage(tabpage)
    vim.api.nvim_set_current_win(win)
  else
    command = command or state.opts.jump
    if type(command) == "function" then
      command(path, item)
    else
      vim.cmd(command .. " " .. vim.fn.fnameescape(path))
    end
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local line_count = math.max(1, vim.api.nvim_buf_line_count(bufnr))
  local row = math.min(math.max(item.range.start.line + 1, 1), line_count)
  local line_text = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local col = results.byte_col(line_text, item.range and item.range.start, item.position_encoding) or 0
  col = math.min(math.max(col, 0), #line_text)
  pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
  vim.cmd("normal! zz")
end

function M.select_current(state, command, reuse_window)
  local item = list.item_from_cursor(state)
  if not item then
    return
  end
  state.lookup_id = state.lookup_id + 1
  lifecycle.close_menu(state)
  vim.schedule(function()
    jump_to_item(state, item, command, reuse_window)
  end)
end

return M
