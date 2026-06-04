local M = {}

local config = require("peeper_picker.config")
local paths = require("peeper_picker.paths")
local list = require("peeper_picker.ui.list")
local lifecycle = require("peeper_picker.ui.lifecycle")

local function item_byte_col(bufnr, item)
  local position = item.range and item.range.start
  if not position then
    return 0
  end
  local ok, byte_col = pcall(
    vim.lsp.util._get_line_byte_from_position,
    bufnr,
    position,
    item.position_encoding or "utf-16"
  )
  return ok and byte_col or position.character
end

local function jump_to_item(state, item, command, reuse_window)
  local path = vim.uri_to_fname(item.uri)
  if reuse_window == nil then
    reuse_window = state.opts.reuse_window
  end
  if reuse_window == nil then
    reuse_window = config.options.reuse_window
  end

  local tabpage, win
  if reuse_window then
    tabpage, win = paths.find_open_window(path)
  end

  if tabpage and win then
    vim.api.nvim_set_current_tabpage(tabpage)
    vim.api.nvim_set_current_win(win)
  else
    command = command or state.opts.jump or config.options.jump
    if type(command) == "function" then
      command(path, item)
    else
      vim.cmd(command .. " " .. vim.fn.fnameescape(path))
    end
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { item.range.start.line + 1, item_byte_col(bufnr, item) })
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
