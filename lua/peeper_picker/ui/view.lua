local M = {}

local text = require("peeper_picker.ui.text")
local highlight = require("peeper_picker.ui.highlight")
local header = require("peeper_picker.ui.header")
local list = require("peeper_picker.ui.list")
local preview_pane = require("peeper_picker.ui.preview_pane")
local filters_mod = require("peeper_picker.filters")
local results = require("peeper_picker.results")

-- Rendering controller: draws the three panes from `state` and owns the
-- view-mode transitions (loading / empty / results) plus navigation redraws.

local function redraw_header(state)
  local menu = state.menu
  if not menu or not menu.header_buf or not vim.api.nvim_buf_is_valid(menu.header_buf) then
    return
  end
  local rendered = header.render(state, menu.list_width or 32, menu.preview_width or 32)
  text.set_buf_lines(menu.header_buf, rendered.lines)
  highlight.header_symbols(menu.header_buf, rendered.highlights)
end

local function redraw_list(state)
  local menu = state.menu
  if not menu or not menu.list_buf or not vim.api.nvim_buf_is_valid(menu.list_buf) then
    return
  end
  text.set_buf_lines(menu.list_buf, list.lines(state, menu))
  vim.api.nvim_buf_clear_namespace(menu.list_buf, -1, 0, -1)
  highlight.apply_results(menu.list_buf, state.items, menu.list_width, 0, 1, #state.items)
end

local function redraw_preview(state, item)
  local menu = state.menu
  if not menu or not menu.preview_buf or not vim.api.nvim_buf_is_valid(menu.preview_buf) then
    return
  end
  local lines, target_line = preview_pane.lines(state, menu, item)
  text.set_buf_lines(menu.preview_buf, lines)
  vim.api.nvim_buf_clear_namespace(menu.preview_buf, -1, 0, -1)
  if item and target_line then
    highlight.preview_definition(menu.preview_buf, target_line, menu.preview_width)
  end
end

local function update_winbar(state)
  local menu = state.menu
  if not menu or not menu.win or not vim.api.nvim_win_is_valid(menu.win) then
    return
  end
  local summary = #state.items > 0 and ("%d results"):format(#state.items) or "no results"
  vim.wo[menu.win].winbar = (" j/k move  ENTER open  f filters  q quit  %s "):format(summary)
end

local function redraw_panes(state, selected_idx)
  local menu = state.menu
  if not menu then
    return
  end

  local idx = selected_idx or 1
  local item = state.items[idx]

  if state.left_lines_dirty then
    list.rebuild(state, idx)
    state.left_lines_dirty = false
  else
    list.hydrate(state, idx)
  end

  redraw_header(state)
  redraw_list(state)
  redraw_preview(state, item)

  if menu.list_win and vim.api.nvim_win_is_valid(menu.list_win) then
    local cursor_row = item and idx or 1
    vim.api.nvim_win_set_cursor(menu.list_win, { cursor_row, 0 })
  end

  if item and idx >= 1 then
    highlight.selected_row(menu.list_buf, idx, menu.list_width)
  end

  update_winbar(state)
end

function M.update_preview(state)
  local menu = state.menu
  if not menu or not menu.list_buf or not vim.api.nvim_buf_is_valid(menu.list_buf) then
    return
  end
  if not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) then
    return
  end

  local row = menu.pending_selected_row or vim.api.nvim_win_get_cursor(menu.list_win)[1]
  menu.pending_selected_row = nil
  local idx = text.clamp(row, 1, math.max(#state.items, 1))
  redraw_panes(state, idx)
end

function M.render_filtered_empty(state)
  local menu = state.menu
  if not menu then
    return
  end
  state.rendered_left_lines = {}
  state.left_lines_dirty = false
  menu.mode = "filtered_empty"
  menu.pending_selected_row = nil
  menu.preview_hint = "Press f to adjust filters."
  menu.list_hint = "No results match filters"
  redraw_panes(state, nil)
end

function M.render_loading(state)
  local menu = state.menu
  if not menu then
    return
  end
  state.all_items, state.items, state.rendered_left_lines = {}, {}, {}
  menu.mode = "loading"
  menu.pending_selected_row = nil
  menu.preview_hint = "Waiting for LSP response..."
  menu.list_hint = "Loading..."
  redraw_panes(state, nil)
end

function M.render_empty(state)
  local menu = state.menu
  if not menu then
    return
  end
  state.all_items, state.items, state.rendered_left_lines = {}, {}, {}
  menu.mode = "empty"
  menu.pending_selected_row = nil
  menu.preview_hint = "Press q or Esc to close."
  menu.list_hint = "No definitions or references found"
  redraw_panes(state, nil)
end

function M.apply_filters(state, preserve_key)
  local keep_key = preserve_key or list.selected_key(state)
  state.items = filters_mod.apply(state.all_items, state.filters, state.source)
  state.left_lines_dirty = true
  if #state.items == 0 then
    M.render_filtered_empty(state)
    if state.render_filter_menu then
      state.render_filter_menu()
    end
    return
  end

  local selected = 1
  if keep_key then
    for i, item in ipairs(state.items) do
      if results.key(item) == keep_key then
        selected = i
        break
      end
    end
  end
  state.menu.mode = "results"
  state.menu.preview_hint = nil
  state.menu.list_hint = nil
  state.menu.pending_selected_row = selected
  redraw_panes(state, selected)
  if state.render_filter_menu then
    state.render_filter_menu()
  end
end

function M.move_cursor(state, delta)
  local menu = state.menu
  if not menu or not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) or #state.items == 0 then
    return
  end
  local count = #state.items
  local current = select(2, list.item_from_cursor(state)) or 1
  local pos
  if math.abs(delta) <= 1 then
    pos = ((current - 1 + delta) % count) + 1
  else
    pos = text.clamp(current + delta, 1, count)
  end
  menu.pending_selected_row = pos
  if menu.list_win and vim.api.nvim_win_is_valid(menu.list_win) then
    vim.api.nvim_win_set_cursor(menu.list_win, { pos, 0 })
  end
  M.update_preview(state)
end

function M.jump_to(state, pos)
  local menu = state.menu
  if not menu or not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) or #state.items == 0 then
    return
  end
  pos = text.clamp(pos, 1, #state.items)
  menu.pending_selected_row = pos
  vim.api.nvim_win_set_cursor(menu.list_win, { pos, 0 })
  M.update_preview(state)
end

return M
