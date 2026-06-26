local M = {}

local text = require("peeper_picker.ui.text")
local paths = require("peeper_picker.paths")
local filters_mod = require("peeper_picker.filters")
local results = require("peeper_picker.results")

local function source_symbol_label(source)
  local word = source.word and source.word ~= "" and source.word or "symbol"
  local kind = source.symbol_kind and source.symbol_kind ~= "" and source.symbol_kind or "symbol"
  return ("[%s] %s"):format(kind, word), word, kind
end

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
  local active = { "results=" .. filters_mod.result_mode(state.filters) }
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

local function scope_path(path)
  if not path or path == "" then
    return "[No Name]"
  end
  return paths.display_path(path)
end

local function scope_context(state)
  local source = state.source or {}
  local scope = state.filters.scope or "workspace"
  local label, target
  if scope == "file" then
    label = "File"
    target = source.path and paths.display_path_from_root(source.path, source.workspace_root) or "[No Name]"
  elseif scope == "dir" then
    label, target = "Directory", scope_path(source.dir)
  else
    label = "Workspace"
    target = scope_path(source.workspace_root or vim.fn.getcwd())
  end

  local parts = { ("%s  %s"):format(label, target) }
  if state.filters.path ~= "" then
    parts[#parts + 1] = "path " .. filters_mod.path_label(state.filters.path)
  end
  if state.filters.extension ~= "" then
    parts[#parts + 1] = "ext " .. filters_mod.extension_label(state.filters.extension)
  end
  return table.concat(parts, "  ·  ")
end

local function result_breakdown(items, word, meta)
  if not items or #items == 0 then
    return ""
  end
  local capped = meta and (meta.matches or meta.files) and true or false
  local symbol = word and word ~= "" and word or "symbol"
  local counts, files, file_count = {}, {}, 0
  for _, item in ipairs(items) do
    local label = results.display_kind(item.kind)
    counts[label] = (counts[label] or 0) + 1
    if item.uri and not files[item.uri] then
      files[item.uri] = true
      file_count = file_count + 1
    end
  end
  local parts = {}
  for _, label in ipairs({ "DEF", "DECL", "REF", "TXT", "COM" }) do
    if counts[label] then
      parts[#parts + 1] = ("%d %s"):format(counts[label], label)
    end
  end
  local plural = file_count == 1 and "" or "s"
  parts[#parts + 1] = ("%d total file%s found with %s"):format(file_count, plural, symbol)
  if capped then
    local limit = meta.match_limit and tostring(meta.match_limit) or "initial"
    parts[#parts + 1] = "text cap " .. limit .. " reached"
  end
  return table.concat(parts, "  ·  ")
end

local function action_highlight(help_line, action)
  if not action or action == "" then
    return nil
  end
  local start_col = help_line:find(action, 1, true)
    or help_line:find("PRESS =", 1, true)
    or help_line:find("EXPANDING", 1, true)
  if not start_col then
    return nil
  end
  local separator = help_line:find(" · ", start_col, true)
  local end_col = separator and (separator - 1) or #(help_line:gsub("%s+$", ""))
  return { row = 0, start_col = start_col - 1, end_col = end_col, group = "PeeperPickerExpandAction" }
end

function M.render(state, left_width, right_width)
  local source = state.source or {}

  local pos = source.line and source.character and (":%d:%d"):format(source.line, source.character) or ""
  local lang = source.filetype and source.filetype ~= "" and source.filetype or "unknown"
  local code = vim.trim(source.line_text or "")
  local snippet = code ~= "" and ("line %d: %s"):format(source.line or 0, code) or "(source line unavailable)"

  local meta = state.result_meta
  local capped = meta and (meta.matches or meta.files) and true or false

  local summary = #state.items > 0 and ("%d%s results"):format(#state.items, capped and "+" or "") or "no results"
  local controls = {}
  local action
  if meta and meta.expanding then
    action = "EXPANDING TEXT RESULTS..."
    controls[#controls + 1] = action
  elseif meta and meta.expandable then
    local limit = meta.match_limit and tostring(meta.match_limit) or tostring(#state.items)
    action = ("PRESS = TO EXPAND %s+ CAPPED RESULTS"):format(limit)
    controls[#controls + 1] = action
  end
  vim.list_extend(controls, {
    "j/k rows",
    "J/K file groups",
    "<CR> open/fold",
    "f filters",
    "? keys",
    "q close",
    summary,
  })
  controls = table.concat(controls, " · ")
  -- reserve room for up to a 4-digit count so centering stays put as it grows
  local controls_reserved = #controls
  if #state.items > 0 then
    controls_reserved = controls_reserved + math.max(0, 4 - #tostring(#state.items))
  end

  local left_cells = {
    ("Searching for: %s"):format(source_symbol_label(source)),
    ("Filters  %s"):format(filter_summary(state)),
    result_breakdown(state.items, source.word, meta),
  }
  local right_cells = {
    ("%s%s  ·  %s"):format(origin_path(source), pos, lang),
    snippet,
    scope_context(state),
  }

  local lines, highlights = {}, {}
  local right_starts = {}
  for i = 1, 3 do
    local left_cell = text.fit_text(left_cells[i] or "", left_width)
    lines[i] = left_cell .. "│" .. text.fit_text(right_cells[i] or "", right_width)
    right_starts[i] = #left_cell + #("│")
  end

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

  local help_line = text.center_text(controls, left_width + right_width + 1, controls_reserved)
  local help_action = action_highlight(help_line, action)

  return {
    lines = lines,
    highlights = highlights,
    help_line = help_line,
    help_highlights = help_action and { help_action } or {},
  }
end

return M
