local M = {}

local text = require("peeper_picker.ui.text")
local preview = require("peeper_picker.preview")
local results = require("peeper_picker.results")
local paths = require("peeper_picker.paths")

local eager_text_radius = 25

local function group_path(state, uri)
  local path = paths.normalize(vim.uri_to_fname(uri))
  if state.source and state.source.workspace_root then
    local relative = paths.relative_to(path, state.source.workspace_root)
    if relative and relative ~= "" then
      return relative
    end
  end
  return paths.display_uri(uri)
end

function M.build_rows(state)
  local groups_by_key, groups = {}, {}
  for item_index, item in ipairs(state.items or {}) do
    local group_key = results.canonical_uri(item.uri)
    local group = groups_by_key[group_key]
    if not group then
      group = {
        group_key = group_key,
        uri = item.uri,
        path = group_path(state, group_key),
        items = {},
        first_item_index = item_index,
        definition_rank = math.huge,
        is_origin = false,
      }
      groups_by_key[group_key] = group
      groups[#groups + 1] = group
    end
    if item.kind == "def" then
      group.definition_rank = math.min(group.definition_rank, 1)
    elseif item.kind == "decl" then
      group.definition_rank = math.min(group.definition_rank, 2)
    end
    group.is_origin = group.is_origin or item.is_origin == true
    group.items[#group.items + 1] = { item = item, item_index = item_index }
  end

  local primary_definition
  for _, group in ipairs(groups) do
    if group.definition_rank < math.huge then
      if
        not primary_definition
        or group.definition_rank < primary_definition.definition_rank
        or (
          group.definition_rank == primary_definition.definition_rank
          and group.path:lower() < primary_definition.path:lower()
        )
      then
        primary_definition = group
      end
    end
  end

  table.sort(groups, function(a, b)
    local pa = a == primary_definition
    local pb = b == primary_definition
    if pa ~= pb then
      return pa
    end
    return a.first_item_index < b.first_item_index
  end)

  local rows = {}
  state.collapsed_groups = state.collapsed_groups or {}
  local live_groups = {}
  for _, group in ipairs(groups) do
    live_groups[group.group_key] = true
  end
  for group_key in pairs(state.collapsed_groups) do
    if not live_groups[group_key] then
      state.collapsed_groups[group_key] = nil
    end
  end
  local display_index = 0
  for _, group in ipairs(groups) do
    local collapsed = state.collapsed_groups[group.group_key] == true
    rows[#rows + 1] = {
      type = "group",
      key = "group:" .. group.group_key,
      group_key = group.group_key,
      uri = group.uri,
      path = group.path,
      result_count = #group.items,
      collapsed = collapsed,
      is_origin = group.is_origin,
      is_primary_definition = group == primary_definition,
    }
    for _, entry in ipairs(group.items) do
      display_index = display_index + 1
      if not collapsed then
        rows[#rows + 1] = {
          type = "item",
          key = results.key(entry.item),
          item = entry.item,
          item_index = entry.item_index,
          display_index = display_index,
        }
      end
    end
  end
  state.list_rows = rows
  return rows
end

function M.row_from_cursor(state)
  local menu = state.menu
  if not menu or not menu.list_win or not vim.api.nvim_win_is_valid(menu.list_win) then
    return nil, nil
  end
  local row = vim.api.nvim_win_get_cursor(menu.list_win)[1]
  return state.list_rows and state.list_rows[row] or nil, row
end

function M.item_from_cursor(state)
  local entry, row = M.row_from_cursor(state)
  return entry and entry.item or nil, row
end

function M.selected_key(state)
  local row = M.row_from_cursor(state)
  return row and row.key or nil
end

local function render_left_line(state, idx, hydrate_text)
  local row = state.list_rows and state.list_rows[idx]
  if not row then
    return ""
  end
  if row.type == "group" then
    local marker = row.collapsed and "▸" or "▾"
    local origin = row.is_origin and " ●" or ""
    return ("%s%s %s"):format(marker, origin, row.path)
  end
  local item = row.item
  if hydrate_text and not item.text then
    item.text = preview.line_at(item.uri, item.range.start.line)
  end
  return results.format_grouped_line(item, row.display_index or row.item_index, #state.items)
end

function M.rebuild(state, selected_idx)
  state.rendered_left_lines = {}
  for i in ipairs(state.list_rows or {}) do
    local hydrate_text = i <= eager_text_radius or math.abs(i - selected_idx) <= eager_text_radius
    state.rendered_left_lines[i] = render_left_line(state, i, hydrate_text)
  end
end

function M.hydrate(state, selected_idx)
  if not state.rendered_left_lines then
    state.rendered_left_lines = {}
  end
  local first = math.max(1, selected_idx - eager_text_radius)
  local last = math.min(#(state.list_rows or {}), selected_idx + eager_text_radius)
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
  if #(state.list_rows or {}) == 0 then
    local width = menu.list_width or 32
    return { text.fit_text(menu.list_hint or "No results", width) }
  end

  local lines = {}
  local width = menu.list_width or 32
  for i in ipairs(state.list_rows) do
    lines[i] = text.fit_text(state.rendered_left_lines[i] or render_left_line(state, i, false), width)
  end
  return lines
end

function M.find_key(state, key)
  if not key then
    return nil
  end
  for i, row in ipairs(state.list_rows or {}) do
    if row.key == key then
      return i
    end
  end
end

function M.default_row(state)
  for i, row in ipairs(state.list_rows or {}) do
    if row.type == "item" then
      return i
    end
  end
  return 1
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
