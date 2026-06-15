local M = {}

local layout = require("peeper_picker.ui.layout")
local highlight = require("peeper_picker.ui.highlight")
local keymap = require("peeper_picker.ui.keymap")
local view = require("peeper_picker.ui.view")
local lifecycle = require("peeper_picker.ui.lifecycle")
local filter_panel = require("peeper_picker.ui.filter_panel")
local jump = require("peeper_picker.ui.jump")

-- Creates the three floating windows (header / list / preview), wires the
-- buffer-local keymaps, and kicks off the loading view.
function M.open(state, lookup_id)
  local prompt = state.filter_prompt
  if prompt and prompt.win and vim.api.nvim_win_is_valid(prompt.win) then
    vim.api.nvim_win_close(prompt.win, true)
  end
  state.filter_prompt = nil
  lifecycle.close_filter_menu(state)
  if state.menu then
    state.menu_closing = true
    lifecycle.close_menu_windows(state.menu)
    state.menu_closing = false
  end
  state.menu = nil
  highlight.ensure()

  local geometry = layout.menu(state.opts)
  local list_width = geometry.list_width
  local preview_width = geometry.preview_width
  local header_width = geometry.header_width
  local pane_height = geometry.pane_height
  local header_height = layout.header_height
  local top = math.max(0, math.floor((vim.o.lines - geometry.total_height) / 2))
  local left = math.max(0, math.floor((vim.o.columns - geometry.total_width) / 2))
  local lower_row = top + header_height + 1
  local preview_col = left + list_width + 1

  local header_buf = vim.api.nvim_create_buf(false, true)
  local header_win = vim.api.nvim_open_win(header_buf, false, {
    relative = "editor",
    width = header_width,
    height = header_height,
    row = top,
    col = left,
    style = "minimal",
    border = state.opts.border,
    title = state.opts.title,
    title_pos = "center",
  })

  local list_buf = vim.api.nvim_create_buf(false, true)
  local preview_buf = vim.api.nvim_create_buf(false, true)
  local preview_win = vim.api.nvim_open_win(preview_buf, false, {
    relative = "editor",
    width = preview_width,
    height = pane_height,
    row = lower_row,
    col = preview_col,
    style = "minimal",
    border = state.opts.border,
    title = " preview ",
    title_pos = "center",
  })
  local list_win = vim.api.nvim_open_win(list_buf, true, {
    relative = "editor",
    width = list_width,
    height = pane_height,
    row = lower_row,
    col = left,
    style = "minimal",
    border = state.opts.border,
    title = " results ",
    title_pos = "center",
  })

  for _, buf in ipairs({ header_buf, list_buf, preview_buf }) do
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].filetype = "peeper-picker"
    vim.bo[buf].swapfile = false
  end
  vim.bo[preview_buf].filetype = "peeper-picker-preview"
  vim.wo[header_win].cursorline = false
  vim.wo[header_win].wrap = false
  vim.wo[list_win].cursorline = false
  vim.wo[list_win].wrap = false
  vim.wo[preview_win].cursorline = false
  vim.wo[preview_win].wrap = false
  state.menu = {
    header_buf = header_buf,
    header_win = header_win,
    list_buf = list_buf,
    list_win = list_win,
    buf = list_buf,
    win = list_win,
    preview_buf = preview_buf,
    preview_win = preview_win,
    mode = "loading",
    lookup_id = lookup_id,
    list_width = list_width,
    preview_width = preview_width,
    pane_height = pane_height,
  }
  for _, win in ipairs({ header_win, list_win, preview_win }) do
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        lifecycle.reset_menu_state(state)
      end,
    })
  end

  view.render_loading(state)
  local bind = keymap.bind
  bind(list_buf, "n", "q", function() lifecycle.close_menu(state) end)
  bind(list_buf, "n", "<Esc>", function() lifecycle.close_menu(state) end)
  bind(list_buf, "n", "<C-c>", function()
    state.lookup_id = state.lookup_id + 1
    lifecycle.close_menu(state)
  end)
  bind(list_buf, "n", "j", function() view.move_cursor(state, vim.v.count1) end)
  bind(list_buf, "n", "<Down>", function() view.move_cursor(state, vim.v.count1) end)
  bind(list_buf, "n", "k", function() view.move_cursor(state, -vim.v.count1) end)
  bind(list_buf, "n", "<Up>", function() view.move_cursor(state, -vim.v.count1) end)
  bind(list_buf, "n", "gg", function() view.jump_to(state, 1) end)
  bind(list_buf, "n", "G", function() view.jump_to(state, #state.items) end)
  bind(list_buf, "n", "f", function() filter_panel.open(state) end)
  bind(list_buf, "n", "<Enter>", function() jump.select_current(state) end)
  bind(list_buf, "n", "<CR>", function() jump.select_current(state) end)
  bind(list_buf, "n", "<C-m>", function() jump.select_current(state) end)
  bind(list_buf, "n", "<C-v>", function() jump.select_current(state, "vsplit", false) end)
  bind(list_buf, "n", "<C-x>", function() jump.select_current(state, "split", false) end)
  bind(list_buf, "n", "<C-t>", function() jump.select_current(state, "tabedit", false) end)
end

return M
