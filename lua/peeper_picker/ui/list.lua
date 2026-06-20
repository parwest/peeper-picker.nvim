local M = {}

local text = require("peeper_picker.ui.text")
local preview = require("peeper_picker.preview")
local results = require("peeper_picker.results")

local eager_text_radius = 25

function M.item_from_cursor(state)
  local menu = state.menu
  if not menu or not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) then
    return nil, nil
  end
  local row = vim.api.nvim_win_get_cursor(menu.list_win)[1]
  return state.items[row], row
end

function M.selected_key(state)
  local item = M.item_from_cursor(state)
  return item and results.key(item) or nil
end

local function render_left_line(state, idx, hydrate_text)
  local item = state.items[idx]
  if not item then
    return ""
  end
  if hydrate_text and not item.text then
    item.text = preview.line_at(item.uri, item.range.start.line)
  end
  return results.format_line(item, idx, #state.items)
end

function M.rebuild(state, selected_idx)
  state.rendered_left_lines = {}
  for i, _ in ipairs(state.items) do
    local hydrate_text = i <= eager_text_radius or math.abs(i - selected_idx) <= eager_text_radius
    state.rendered_left_lines[i] = render_left_line(state, i, hydrate_text)
  end
end

function M.hydrate(state, selected_idx)
  if not state.rendered_left_lines then
    state.rendered_left_lines = {}
  end
  local first = math.max(1, selected_idx - eager_text_radius)
  local last = math.min(#state.items, selected_idx + eager_text_radius)
  local changed_first, changed_last
  for i = first, last do
    local line = render_left_line(state, i, true)
    if line ~= state.rendered_left_lines[i] then
      state.rendered_left_lines[i] = line
      changed_first = changed_first or i
      changed_last = i
    end
  end
  return changed_first, changed_last
end

function M.lines(state, menu)
  if #state.items == 0 then
    local width = menu.list_width or 32
    return { text.fit_text(menu.list_hint or "No results", width) }
  end

  local lines = {}
  local width = menu.list_width or 32
  for i in ipairs(state.items) do
    lines[i] = text.fit_text(state.rendered_left_lines[i] or render_left_line(state, i, false), width)
  end
  return lines
end

function M.fit_range(state, menu, first, last)
  local width = menu.list_width or 32
  local lines = {}
  for i = first, last do
    lines[#lines + 1] = text.fit_text(state.rendered_left_lines[i] or render_left_line(state, i, false), width)
  end
  return lines
end

return M
