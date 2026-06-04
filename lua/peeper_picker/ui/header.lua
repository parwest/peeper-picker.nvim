local M = {}

local text = require("peeper_picker.ui.text")
local paths = require("peeper_picker.paths")
local filters_mod = require("peeper_picker.filters")

local function source_symbol_label(source)
  local word = source.word and source.word ~= "" and source.word or "symbol"
  local kind = source.symbol_kind and source.symbol_kind ~= "" and source.symbol_kind or "symbol"
  return ("[%s] %s"):format(kind, word), word, kind
end

-- Byte range of the symbol name within the (clipped) header line, so it can be
-- underlined. Returns nil, nil when it would fall outside the visible area.
function M.symbol_highlight(source, width)
  local _, word, kind = source_symbol_label(source)
  local left_text = ("Searching for: [%s] %s"):format(kind, word)
  local visible_left = text.fit_text(left_text, width)
  local visible_limit = #visible_left
  if text.display_width(left_text) > width then
    visible_limit = math.max(0, visible_limit - #("…"))
  end

  local prefix = ("Searching for: [%s] "):format(kind)
  local start_col = #prefix
  local end_col = start_col + #word
  if start_col >= visible_limit then
    return nil, nil
  end

  start_col = math.max(0, math.min(start_col, visible_limit))
  end_col = math.max(start_col, math.min(end_col, visible_limit))
  if end_col <= start_col then
    return nil, nil
  end

  return start_col, end_col
end

function M.lines(state, left_width, right_width)
  local source = state.source or {}
  local path = source.path and paths.display_path(source.path) or "[No Name]"
  local pos = source.line and source.character and (":%d:%d"):format(source.line, source.character) or ""
  local root = source.workspace_root and paths.display_path(source.workspace_root) or vim.fn.getcwd()
  local active_filters = { "results=" .. filters_mod.result_label(state.filters) }
  if state.filters.scope ~= "workspace" then
    table.insert(active_filters, "scope=" .. filters_mod.scope_label(state.filters.scope))
  end
  if state.filters.path ~= "" then
    table.insert(active_filters, "path=" .. filters_mod.field_label(state.filters.path))
  end
  if state.filters.extension ~= "" then
    table.insert(active_filters, "ext=" .. filters_mod.extension_label(state.filters.extension))
  end
  local filter_summary = table.concat(active_filters, "  ")
  return {
    text.fit_text(("Searching for: %s"):format(source_symbol_label(source)), left_width) .. "│" .. text.fit_text(path .. pos, right_width),
    text.fit_text(("Filters  %s"):format(filter_summary), left_width) .. "│" .. text.fit_text("Workspace  " .. root, right_width),
    string.rep("─", left_width) .. "┼" .. string.rep("─", right_width),
  }
end

return M
