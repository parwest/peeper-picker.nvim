local M = {}

local keymap = require("peeper_picker.ui.keymap")
local layout = require("peeper_picker.ui.layout")
local lifecycle = require("peeper_picker.ui.lifecycle")
local text = require("peeper_picker.ui.text")
local floating = require("peeper_picker.ui.floating")

local function key_row(left_key, left_desc, right_key, right_desc)
  return ("%-14s %-32s  %-14s %s"):format(
    left_key or "",
    left_desc or "",
    right_key or "",
    right_desc or ""
  )
end

local function picker_lines(state)
  local expandable = state.result_meta and state.result_meta.expandable
  local expand_desc = expandable and "expand capped search" or "expand when capped"
  return {
    "keymap:",
    "",
    key_row("j / k", "next / previous result", "J / K", "next / previous file group"),
    key_row("<Up>/<Down>", "next / previous result", "gg / G", "first / last result"),
    key_row("count+j/k", "jump multiple results", "count+J/K", "jump multiple file groups"),
    "",
    key_row("<CR>", "open result or fold group", "<C-v>", "open in vertical split"),
    key_row("zo / zc", "open / close group", "<C-x>", "open in horizontal split"),
    key_row("za", "toggle current group", "<C-t>", "open in tab"),
    key_row("zR / zM", "open / close all groups", "f", "filters"),
    key_row("=", expand_desc, "?", "toggle this help"),
    key_row("q / <Esc>", "close this help", "<C-c>", "cancel lookup"),
    "",
    "",
    "",
    "",
    "",
  }
end

local function lines_for(state)
  return picker_lines(state)
end

local function fit_lines(lines, width)
  local fitted = {}
  for i, line in ipairs(lines) do
    fitted[i] = " " .. text.fit_text(line, math.max(0, width - 1))
  end
  return fitted
end

local function valid_return_win(state, win)
  return win and vim.api.nvim_win_is_valid(win) and lifecycle.is_picker_window(state, win)
end

local function fallback_return_win(state)
  local menu = state.menu
  if menu and menu.list_win and vim.api.nvim_win_is_valid(menu.list_win) then
    return menu.list_win
  end
end

local function current_return_win(state)
  local current = vim.api.nvim_get_current_win()
  if valid_return_win(state, current) then
    return current
  end
  return fallback_return_win(state)
end

local function set_help_lines(help, lines)
  if not help or not help.buf or not vim.api.nvim_buf_is_valid(help.buf) then
    return
  end
  text.set_buf_lines(help.buf, fit_lines(lines, help.width or 1))
end

local function move_cursor(state, delta)
  local help = state.key_help
  if not help or not help.win or not vim.api.nvim_win_is_valid(help.win) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(help.win)[1] + (delta or 0)
  row = text.clamp(row, 1, help.line_count or help.height or 1)
  pcall(vim.api.nvim_win_set_cursor, help.win, { row, 0 })
end

local function pin_cursor(state)
  move_cursor(state, 0)
end

local function bind_close(buf, state)
  local function close()
    lifecycle.close_key_help(state)
  end
  keymap.bind(buf, "n", "q", close)
  keymap.bind(buf, "n", "<Esc>", close)
  keymap.bind(buf, "n", "?", close)
  keymap.bind(buf, "n", "<CR>", close)
  keymap.bind(buf, "n", "<C-c>", function()
    state.lookup_id = (state.lookup_id or 0) + 1
    lifecycle.close_menu(state)
  end)

  keymap.bind(buf, "n", "j", function()
    move_cursor(state, vim.v.count1)
  end)
  keymap.bind(buf, "n", "<Down>", function()
    move_cursor(state, vim.v.count1)
  end)
  keymap.bind(buf, "n", "k", function()
    move_cursor(state, -vim.v.count1)
  end)
  keymap.bind(buf, "n", "<Up>", function()
    move_cursor(state, -vim.v.count1)
  end)
  keymap.bind(buf, "n", "gg", function()
    move_cursor(state, -math.huge)
  end)
  keymap.bind(buf, "n", "G", function()
    move_cursor(state, math.huge)
  end)

  local pinned_keys = {
    "h",
    "l",
    "<Left>",
    "<Right>",
    "0",
    "$",
    "^",
    "_",
    "w",
    "W",
    "b",
    "B",
    "e",
    "E",
    "ge",
    "gE",
  }
  for _, lhs in ipairs(pinned_keys) do
    keymap.bind(buf, "n", lhs, function()
      pin_cursor(state)
    end)
  end
end

function M.open(state)
  local menu = state.menu
  if not menu or not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) then
    return false
  end

  if state.key_help then
    lifecycle.close_key_help(state)
    return true
  end

  local lines = lines_for(state)
  local geometry, err = layout.key_help(state.opts, #lines)
  if not geometry then
    vim.notify(err, vim.log.levels.WARN)
    return false
  end

  local buf, win = floating.open({
    name = "peeper-picker://keys",
    filetype = "peeper-picker-key-help",
    width = geometry.width,
    height = geometry.height,
    row = geometry.row,
    col = geometry.col,
    border = state.opts.border,
    title = " keys ",
    zindex = 80,
    modifiable = false,
    win_options = {
      cursorline = false,
      wrap = false,
    },
  })

  state.key_help = {
    buf = buf,
    win = win,
    return_win = current_return_win(state),
    width = geometry.width,
    height = geometry.height,
    line_count = #lines,
  }
  set_help_lines(state.key_help, lines)
  pin_cursor(state)
  bind_close(buf, state)

  if state.menu and state.menu.augroup then
    vim.api.nvim_create_autocmd("WinClosed", {
      group = state.menu.augroup,
      pattern = tostring(win),
      once = true,
      callback = function()
        if state.key_help and state.key_help.win == win then
          state.key_help = nil
        end
      end,
    })
  end
  return true
end

function M.reflow(state)
  local help = state.key_help
  if not help or not help.win or not vim.api.nvim_win_is_valid(help.win) then
    return
  end
  local lines = lines_for(state)
  local geometry, err = layout.key_help(state.opts, #lines)
  if not geometry then
    vim.notify(err, vim.log.levels.WARN)
    lifecycle.close_key_help(state)
    return
  end
  floating.reconfigure(help.win, {
    width = geometry.width,
    height = geometry.height,
    row = geometry.row,
    col = geometry.col,
    border = state.opts.border,
    title = " keys ",
    zindex = 80,
    win_options = {
      cursorline = false,
      wrap = false,
    },
  })
  help.width = geometry.width
  help.height = geometry.height
  help.line_count = #lines
  set_help_lines(help, lines)
  pin_cursor(state)
end

return M
