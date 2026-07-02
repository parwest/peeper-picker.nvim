local M = {}

local config = require("peeper_picker.config")
local filters = require("peeper_picker.filters")
local grep = require("peeper_picker.grep")
local history = require("peeper_picker.history")
local keywords = require("peeper_picker.keywords")
local lsp = require("peeper_picker.lsp")
local paths = require("peeper_picker.paths")
local preview = require("peeper_picker.preview")
local results = require("peeper_picker.results")
local ui = require("peeper_picker.ui")

local state = {
  menu = nil,
  filter_menu = nil,
  filter_prompt = nil,
  all_items = {},
  items = {},
  list_rows = {},
  collapsed_groups = {},
  filters = filters.defaults(),
  source = {},
  lookup_id = 0,
  rendered_left_lines = {},
  left_lines_dirty = true,
  opts = config.options,
}

local active_default_keymaps = {}

local function cursor_on_keyword(bufnr, cursor, word)
  local row = cursor[1] - 1
  local col = cursor[2]
  if keywords.is_ignored(word, vim.bo[bufnr].filetype) then
    return true
  end
  if keywords.has_keyword_capture(bufnr, row, col) then
    return true
  end
  if not vim.treesitter or not vim.treesitter.get_node then
    return false
  end
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col } })
  if not ok or not node then
    return false
  end
  local ntype = node:type()
  if ntype:find("keyword", 1, true) then
    return true
  end
  -- some grammars name a keyword node after the keyword text itself
  if word and word ~= "" and ntype == word then
    return true
  end
  return false
end

local function setup_keymaps()
  for _, lhs in ipairs(active_default_keymaps) do
    pcall(vim.keymap.del, "n", lhs)
  end
  active_default_keymaps = {}

  local keymaps = config.options.default_keymaps or {}
  if not keymaps.enabled then
    return
  end

  local binds = {
    { keymaps.find, M.find, "Peeper Picker" },
    { keymaps.history, M.history, "Peeper Picker History" },
  }
  for _, bind in ipairs(binds) do
    local lhs, fn, desc = bind[1], bind[2], bind[3]
    if lhs and lhs ~= "" then
      vim.keymap.set("n", lhs, fn, { desc = desc })
      active_default_keymaps[#active_default_keymaps + 1] = lhs
    end
  end
end

local POSITION_ENCODINGS = { "utf-8", "utf-16", "utf-32" }

-- position params for an arbitrary buffer location, so a peep can target a stored
-- anchor without moving the cursor or relying on the current window
local function position_params(bufnr, row, col)
  local uri = vim.uri_from_bufnr(bufnr)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  col = math.max(0, math.min(col, #line))
  local params = {}
  for _, encoding in ipairs(POSITION_ENCODINGS) do
    local character = col
    if encoding ~= "utf-8" then
      local ok, idx = pcall(vim.str_utfindex, line, encoding, col, false)
      if ok then
        character = idx
      end
    end
    params[encoding] = {
      textDocument = { uri = uri },
      position = { line = row, character = character },
    }
  end
  return params
end

-- spec: { bufnr, row (1-based), col (0-based byte), word, symbol_kind, record }
local function run_peep(spec)
  local bufnr = spec.bufnr
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end
  preview.reset()
  paths.reset_cache()
  state.lookup_id = state.lookup_id + 1
  local lookup_id = state.lookup_id

  if not spec.text_only and lsp.supported_count(bufnr) == 0 then
    ui.close_menu(state)
    vim.notify("peeper-picker.nvim: no supported LSP definition/reference methods", vim.log.levels.WARN)
    return
  end

  local row, col, word = spec.row, spec.col, spec.word
  if spec.record ~= false and word and word ~= "" then
    history.record(bufnr, row - 1, col, word)
  end

  local current_path = vim.api.nvim_buf_get_name(bufnr)
  current_path = current_path ~= "" and paths.normalize(current_path) or nil
  state.opts = config.options
  state.filters = filters.defaults()
  state.list_rows = {}
  state.collapsed_groups = {}
  state.result_meta = nil
  state.expand_results = nil
  state.source = {
    path = current_path,
    dir = current_path and paths.normalize(vim.fn.fnamemodify(current_path, ":p:h")) or nil,
    workspace_root = paths.workspace_root(bufnr, current_path),
    filetype = vim.bo[bufnr].filetype,
    symbol_kind = spec.symbol_kind or "symbol",
    word = word,
    line = row,
    character = col + 1,
    line_text = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or "",
  }
  local params_by_encoding = position_params(bufnr, row - 1, col)

  if not ui.open_menu(state, lookup_id) then
    return
  end

  local function active_lookup()
    local menu = state.menu
    return lookup_id == state.lookup_id and menu and menu.lookup_id == lookup_id
  end

  -- lsp results win; grep adds textual hits it missed, deduped by location
  local lsp_items, grep_items = {}, {}
  local lsp_done, grep_done = false, false
  local grep_scan_id = 0

  local function rebuild()
    if not active_lookup() then
      return
    end
    local merged, seen = {}, {}
    for _, item in ipairs(lsp_items) do
      seen[results.key(item)] = true
      merged[#merged + 1] = item
    end
    for _, item in ipairs(grep_items) do
      local key = results.key(item)
      if not seen[key] then
        seen[key] = true
        merged[#merged + 1] = item
      end
    end
    -- a text-only peep hunts a defunct name; the anchor now holds the renamed
    -- symbol, which is not a match, so don't inject it as an origin row
    if not spec.text_only then
      if not results.mark_origin(merged, state.source) then
        local origin = results.origin_item(state.source)
        if origin then
          merged[#merged + 1] = origin
        end
      end
    end
    results.sort(merged)
    state.all_items = merged
    if #merged > 0 then
      ui.apply_filters(state)
    elseif lsp_done and grep_done then
      ui.render_empty(state)
    end
  end

  -- coalesce streaming grep batches to one render per frame with a guaranteed trailing render
  local schedule_rebuild
  local rebuild_armed = false
  local rebuild_dirty = false

  local function flush_rebuild()
    rebuild_armed = false
    if rebuild_dirty then
      rebuild_dirty = false
      schedule_rebuild()
    end
  end

  function schedule_rebuild()
    if rebuild_armed then
      rebuild_dirty = true
      return
    end
    rebuild_armed = true
    rebuild()
    vim.defer_fn(flush_rebuild, 24)
  end

  -- text_only peeps a defunct name (e.g. a former name after a rename); the LSP
  -- can't resolve a name that no longer exists, so skip it and let grep find the
  -- textual stragglers, the same way a peep of a comment/string word already does
  if spec.text_only then
    lsp_done = true
  else
    lsp.collect(bufnr, params_by_encoding, function(items)
      vim.schedule(function()
        lsp_items = items
        lsp_done = true
        schedule_rebuild()
      end)
    end)
  end

  if word and word ~= "" then
    local function expanded_limit()
      local value = tonumber(state.opts.expanded_match_limit) or config.defaults.expanded_match_limit
      return math.max(1, math.floor(value))
    end
    local function run_grep(match_limit, expanded)
      grep_scan_id = grep_scan_id + 1
      local scan_id = grep_scan_id
      grep_items = {}
      grep_done = false

      grep.collect({
        root = state.source.workspace_root,
        word = word,
        match_limit = match_limit,
        is_cancelled = function()
          return not active_lookup() or scan_id ~= grep_scan_id
        end,
      }, function(batch)
        if scan_id ~= grep_scan_id or not active_lookup() then
          return
        end
        for _, item in ipairs(batch) do
          grep_items[#grep_items + 1] = item
        end
        schedule_rebuild()
      end, function(meta)
        if scan_id ~= grep_scan_id or not active_lookup() then
          return
        end
        meta = meta or {}
        local expand_limit = expanded_limit()
        meta.expandable = not expanded
          and meta.matches == true
          and expand_limit > (meta.match_limit or 0)
        grep_done = true
        state.result_meta = meta
        schedule_rebuild()
      end)
    end

    state.expand_results = function()
      local meta = state.result_meta
      if not active_lookup() then
        return false
      end
      if not meta then
        return false, "text search is still running"
      end
      if not meta.expandable then
        if meta.matches or meta.files then
          return false, "expanded_match_limit is not above the current cap"
        end
        return false, "text search is not capped"
      end
      state.result_meta = {
        matches = true,
        match_limit = meta.match_limit,
        expanding = true,
      }
      schedule_rebuild()
      run_grep(expanded_limit(), true)
      return true
    end

    run_grep(nil, false)
  else
    grep_done = true
  end
end

function M.find()
  local bufnr = vim.api.nvim_get_current_buf()
  if lsp.supported_count(bufnr) == 0 then
    ui.close_menu(state)
    vim.notify("peeper-picker.nvim: no supported LSP definition/reference methods", vim.log.levels.WARN)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_word = vim.fn.expand("<cword>")
  if cursor_on_keyword(bufnr, cursor, cursor_word) then
    return
  end
  local source_symbol = lsp.source_symbol(bufnr, cursor, cursor_word) or {}
  local word = source_symbol.name and source_symbol.name ~= "" and source_symbol.name or cursor_word
  run_peep({
    bufnr = bufnr,
    row = cursor[1],
    col = cursor[2],
    word = word,
    symbol_kind = source_symbol.kind,
  })
end

function M.history()
  local function open()
    ui.open_history(state, history.list(), function(choice)
      run_peep({
        bufnr = choice.bufnr,
        row = choice.row + 1,
        col = choice.col,
        word = choice.word,
        text_only = choice.text_only,
      })
    end, function()
      -- clearing re-opens the menu so it shows its empty state as confirmation
      history.clear()
      open()
    end)
  end
  open()
end

function M.setup(opts)
  config.setup(opts)
  state.opts = config.options
  setup_keymaps()
end

return M
