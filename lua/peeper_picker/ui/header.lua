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

local function origin_path(source)
  if not source.path or source.path == "" then
    return "[No Name]"
  end
  if source.workspace_root then
    local relative = paths.relative_to(source.path, source.workspace_root)
    if relative and relative ~= "" then
      return relative
    end
  end
  return paths.display_path(source.path)
end

local function filter_summary(state)
  local active = { "results=" .. filters_mod.result_label(state.filters) }
  if state.filters.scope ~= "workspace" then
    table.insert(active, "scope=" .. filters_mod.scope_label(state.filters.scope))
  end
  if state.filters.path ~= "" then
    table.insert(active, "path=" .. filters_mod.field_label(state.filters.path))
  end
  if state.filters.extension ~= "" then
    table.insert(active, "ext=" .. filters_mod.extension_label(state.filters.extension))
  end
  return table.concat(active, "  ")
end

function M.render(state, left_width, right_width)
  local source = state.source or {}

  local pos = source.line and source.character and (":%d:%d"):format(source.line, source.character) or ""
  local lang = source.filetype and source.filetype ~= "" and source.filetype or "unknown"
  local root = source.workspace_root and paths.display_path(source.workspace_root) or vim.fn.getcwd()
  local code = vim.trim(source.line_text or "")
  local snippet = code ~= "" and ("line %d  %s"):format(source.line or 0, code) or "(source line unavailable)"

  local left_cells = {
    ("Searching for: %s"):format(source_symbol_label(source)),
    ("Filters  %s"):format(filter_summary(state)),
    "",
  }
  local right_cells = {
    ("%s%s  ·  %s"):format(origin_path(source), pos, lang),
    snippet,
    ("Workspace  %s"):format(root),
  }

  local lines, highlights = {}, {}
  local right_starts = {}
  for i = 1, 3 do
    local left_cell = text.fit_text(left_cells[i] or "", left_width)
    lines[i] = left_cell .. "│" .. text.fit_text(right_cells[i] or "", right_width)
    right_starts[i] = #left_cell + #("│")
  end
  lines[4] = string.rep("─", left_width) .. "┼" .. string.rep("─", right_width)

  local left_start, left_end = M.symbol_highlight(source, left_width)
  if left_start and left_end then
    highlights[#highlights + 1] = { row = 0, start_col = left_start, end_col = left_end }
  end

  if code ~= "" then
    local trimmed = (text.fit_text(snippet, right_width):gsub("%s+$", ""))
    if #trimmed > 0 then
      highlights[#highlights + 1] = { row = 1, start_col = right_starts[2], end_col = right_starts[2] + #trimmed }
    end
  end

  return { lines = lines, highlights = highlights }
end

return M
