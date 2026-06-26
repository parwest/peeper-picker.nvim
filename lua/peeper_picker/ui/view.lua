local M = {}

local text = require("peeper_picker.ui.text")
local highlight = require("peeper_picker.ui.highlight")
local header = require("peeper_picker.ui.header")
local list = require("peeper_picker.ui.list")
local preview_pane = require("peeper_picker.ui.preview_pane")
local filters_mod = require("peeper_picker.filters")
local results = require("peeper_picker.results")

local function redraw_header(state)
  local menu = state.menu
  if not menu or not menu.header_buf or not vim.api.nvim_buf_is_valid(menu.header_buf) then
    return
  end
  local rendered = header.render(
    state,
    menu.header_left_width or menu.list_width or 32,
    menu.header_right_width or menu.preview_width or 32
  )
  text.set_buf_lines(menu.header_buf, rendered.lines)
  text.set_buf_lines(menu.help_buf, { rendered.help_line })
  highlight.header_symbols(menu.header_buf, rendered.highlights)
  highlight.help_actions(menu.help_buf, rendered.help_highlights)
end

local function redraw_list_text(state, changed)
  local menu = state.menu
  if not menu or not menu.list_buf or not vim.api.nvim_buf_is_valid(menu.list_buf) then
    return
  end
  if changed == "all" then
    text.set_buf_lines(menu.list_buf, list.lines(state, menu))
  elseif changed then
    local first, last = changed.first, changed.last
    text.set_buf_line_range(menu.list_buf, first - 1, last, list.fit_range(state, menu, first, last))
  end
end

-- highlight only the rows visible in the list window; runs after every redraw and
-- on scroll, so the cost is bounded to a viewport no matter how many results there are
local function highlight_viewport(state)
  local menu = state.menu
  if not menu or not menu.list_buf or not vim.api.nvim_buf_is_valid(menu.list_buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(menu.list_buf, highlight.results_ns, 0, -1)
  local rows = state.list_rows or {}
  if #rows == 0 or not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) then
    return
  end
  local bounds = vim.api.nvim_win_call(menu.list_win, function()
    return { top = vim.fn.line("w0"), bot = vim.fn.line("w$") }
  end)
  local first = math.max(1, bounds.top)
  local last = math.min(#rows, bounds.bot)
  if last >= first then
    highlight.apply_results(menu.list_buf, rows, first - 1, first, last - first + 1)
  end
end

function M.highlight_viewport(state)
  highlight_viewport(state)
end

local function set_preview_syntax(menu, item)
  local filetype = ""
  if item then
    local ok, detected = pcall(vim.filetype.match, { filename = vim.uri_to_fname(item.uri) })
    filetype = ok and detected or ""
  end
  if menu.preview_filetype == filetype then
    return
  end
  menu.preview_filetype = filetype
  vim.api.nvim_buf_call(menu.preview_buf, function()
    vim.cmd("silent! syntax clear")
    vim.b.current_syntax = nil
    vim.bo[menu.preview_buf].syntax = filetype
  end)
end

local function set_preview_view(menu, target_line, start_col, end_col, line, gutter_width)
  local cursor_line, cursor_col, leftcol = 1, 0, 0
  if target_line and start_col and end_col then
    cursor_line = target_line
    cursor_col = start_col
    local content_width = math.max(1, (menu.preview_width or 1) - (gutter_width or 0))
    local match_start = vim.fn.strdisplaywidth((line or ""):sub(1, start_col))
    local match_end = vim.fn.strdisplaywidth((line or ""):sub(1, end_col))
    if match_end >= content_width then
      leftcol = math.max(0, match_start - math.floor(content_width / 3))
    end
  end

  pcall(vim.api.nvim_win_set_cursor, menu.preview_win, { cursor_line, cursor_col })
  vim.api.nvim_win_call(menu.preview_win, function()
    local view = vim.fn.winsaveview()
    view.topline = 1
    view.leftcol = leftcol
    view.skipcol = 0
    vim.fn.winrestview(view)
  end)
end

local function redraw_preview(state, item, row)
  local menu = state.menu
  if not menu or not menu.preview_buf or not vim.api.nvim_buf_is_valid(menu.preview_buf) then
    return
  end
  local lines, target_line, first_line, content_count = preview_pane.lines(state, menu, item, row)
  text.set_buf_lines(menu.preview_buf, lines)
  set_preview_syntax(menu, item)
  highlight.clear_preview(menu.preview_buf)
  local start_col, end_col, target_text, gutter_width
  if item and target_line and first_line then
    target_text = lines[target_line] or ""
    start_col, end_col = results.byte_span(item, target_text, state.source and state.source.word)
    gutter_width = highlight.preview_context(menu.preview_buf, first_line, content_count, target_line, start_col, end_col)
  end
  set_preview_view(menu, target_line, start_col, end_col, target_text, gutter_width)
end

local function redraw_panes(state, selected_idx)
  local menu = state.menu
  if not menu then
    return
  end

  local idx = selected_idx or 1
  local row = state.list_rows and state.list_rows[idx]
  local item = row and row.item or nil

  local changed
  if state.left_lines_dirty or #state.items == 0 then
    list.rebuild(state, idx)
    state.left_lines_dirty = false
    changed = "all"
  else
    local cfirst, clast = list.hydrate(state, idx)
    changed = cfirst and { first = cfirst, last = clast } or nil
  end

  local list_win_valid = menu.list_win and vim.api.nvim_win_is_valid(menu.list_win)
  local saved_view = list_win_valid and vim.api.nvim_win_call(menu.list_win, vim.fn.winsaveview) or nil

  if changed == "all" then
    redraw_header(state)
  end
  redraw_list_text(state, changed)
  redraw_preview(state, item, row)

  if list_win_valid then
    if saved_view then
      vim.api.nvim_win_call(menu.list_win, function()
        vim.fn.winrestview(saved_view)
      end)
    end
    local cursor_row = row and idx or 1
    vim.api.nvim_win_set_cursor(menu.list_win, { cursor_row, 0 })
  end

  highlight_viewport(state)

  highlight.selected_row(menu.list_buf, row and idx or nil)
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
  local idx = text.clamp(row, 1, math.max(#(state.list_rows or {}), 1))
  redraw_panes(state, idx)
end

function M.render_filtered_empty(state)
  local menu = state.menu
  if not menu then
    return
  end
  state.rendered_left_lines, state.list_rows = {}, {}
  state.left_lines_dirty = false
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
  state.all_items, state.items, state.list_rows, state.rendered_left_lines = {}, {}, {}, {}
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
  state.all_items, state.items, state.list_rows, state.rendered_left_lines = {}, {}, {}, {}
  menu.pending_selected_row = nil
  menu.preview_hint = "Press q or Esc to close."
  menu.list_hint = "No definitions or references found"
  redraw_panes(state, nil)
end

function M.apply_filters(state, preserve_key)
  local menu = state.menu
  local keep_key = preserve_key
  if keep_key == nil and menu and menu.selection_locked then
    keep_key = list.selected_key(state)
  end
  state.items = filters_mod.apply(state.all_items, state.filters, state.source)
  list.build_rows(state)
  state.left_lines_dirty = true
  if #state.items == 0 then
    M.render_filtered_empty(state)
    if state.render_filter_menu then
      state.render_filter_menu()
    end
    return
  end

  local selected = list.find_key(state, keep_key) or list.default_row(state)
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
  if not menu or not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) or #(state.list_rows or {}) == 0 then
    return
  end
  local count = #state.list_rows
  local current = select(2, list.row_from_cursor(state)) or 1
  local pos
  if math.abs(delta) <= 1 then
    pos = ((current - 1 + delta) % count) + 1
  else
    pos = text.clamp(current + delta, 1, count)
  end
  menu.selection_locked = true
  menu.pending_selected_row = pos
  if menu.list_win and vim.api.nvim_win_is_valid(menu.list_win) then
    vim.api.nvim_win_set_cursor(menu.list_win, { pos, 0 })
  end
  M.update_preview(state)
end

function M.jump_to(state, pos)
  local menu = state.menu
  if not menu or not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) or #(state.list_rows or {}) == 0 then
    return
  end
  pos = text.clamp(pos, 1, #state.list_rows)
  menu.selection_locked = true
  menu.pending_selected_row = pos
  vim.api.nvim_win_set_cursor(menu.list_win, { pos, 0 })
  M.update_preview(state)
end

local function jump_group(state, direction, count)
  local rows = state.list_rows or {}
  if #rows == 0 then
    return
  end
  local current = select(2, list.row_from_cursor(state)) or 1
  while current > 1 and rows[current].type ~= "group" do
    current = current - 1
  end
  local remaining = math.max(1, count or 1)
  for offset = 1, #rows * remaining do
    local pos = ((current - 1 + (offset * direction)) % #rows) + 1
    local row = rows[pos]
    if row.type == "group" then
      remaining = remaining - 1
      if remaining == 0 then
        M.jump_to(state, pos)
        return
      end
    end
  end
end

function M.next_group(state, count)
  jump_group(state, 1, count)
end

function M.previous_group(state, count)
  jump_group(state, -1, count)
end

local function rebuild_groups(state, keep_key)
  list.build_rows(state)
  state.left_lines_dirty = true
  local selected = list.find_key(state, keep_key) or 1
  state.menu.pending_selected_row = selected
  redraw_panes(state, selected)
end

-- use the current group header or the nearest group header above an item row
local function controlling_group(state)
  local rows = state.list_rows or {}
  local _, current = list.row_from_cursor(state)
  for i = current or 1, 1, -1 do
    if rows[i] and rows[i].type == "group" then
      return rows[i]
    end
  end
end

-- mode is "open", "close", or "toggle"
function M.fold_group(state, mode)
  if not state.menu then
    return false
  end
  local group = controlling_group(state)
  if not group then
    return false
  end
  local collapsed = state.collapsed_groups[group.group_key] == true
  local target
  if mode == "open" then
    target = false
  elseif mode == "close" then
    target = true
  else
    target = not collapsed
  end
  if target ~= collapsed then
    state.menu.selection_locked = true
    state.collapsed_groups[group.group_key] = target or nil
    rebuild_groups(state, group.key)
  end
  return true
end

function M.toggle_group(state)
  local row = list.row_from_cursor(state)
  if not row or row.type ~= "group" then
    return false
  end
  return M.fold_group(state, "toggle")
end

function M.set_all_groups(state, collapsed)
  if not state.menu then
    return
  end
  state.menu.selection_locked = true
  state.collapsed_groups = {}
  if collapsed then
    for _, row in ipairs(state.list_rows or {}) do
      if row.type == "group" then
        state.collapsed_groups[row.group_key] = true
      end
    end
  end
  local keep_key = list.selected_key(state)
  rebuild_groups(state, keep_key)
end

return M
