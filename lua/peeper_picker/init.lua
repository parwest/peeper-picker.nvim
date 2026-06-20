local M = {}

local config = require("peeper_picker.config")
local filters = require("peeper_picker.filters")
local grep = require("peeper_picker.grep")
local grep_classify = require("peeper_picker.grep_classify")
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
  filters = filters.defaults(),
  source = {},
  lookup_id = 0,
  rendered_left_lines = {},
  left_lines_dirty = true,
  opts = config.options,
}

local active_default_keymap = nil

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
  if active_default_keymap then
    pcall(vim.keymap.del, "n", active_default_keymap)
    active_default_keymap = nil
  end

  local keymaps = config.options.default_keymaps or {}
  if not keymaps.enabled then
    return
  end

  local find_key = keymaps.find
  if find_key and find_key ~= "" then
    vim.keymap.set("n", find_key, M.find, { desc = "Peeper Picker" })
    active_default_keymap = find_key
  end
end

function M.find()
  local bufnr = vim.api.nvim_get_current_buf()
  preview.reset()
  paths.reset_cache()
  state.lookup_id = state.lookup_id + 1
  local lookup_id = state.lookup_id

  if lsp.supported_count(bufnr) == 0 then
    ui.close_menu(state)
    vim.notify("peeper-picker.nvim: no supported LSP definition/reference methods", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_word_pre = vim.fn.expand("<cword>")
  if cursor_on_keyword(bufnr, cursor, cursor_word_pre) then
    return
  end
  local current_path = vim.api.nvim_buf_get_name(bufnr)
  current_path = current_path ~= "" and paths.normalize(current_path) or nil
  local cursor_word = vim.fn.expand("<cword>")
  local source_symbol = lsp.source_symbol(bufnr, cursor, cursor_word) or {}
  local word = source_symbol.name and source_symbol.name ~= "" and source_symbol.name or cursor_word
  state.opts = config.options
  state.filters = filters.defaults()
  state.result_meta = nil
  state.expand_results = nil
  state.source = {
    path = current_path,
    dir = current_path and paths.normalize(vim.fn.fnamemodify(current_path, ":p:h")) or nil,
    workspace_root = paths.workspace_root(bufnr, current_path),
    filetype = vim.bo[bufnr].filetype,
    symbol_kind = source_symbol.kind or "symbol",
    word = word,
    line = cursor[1],
    character = cursor[2] + 1,
    line_text = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or "",
  }
  local params_by_encoding = {}
  for _, encoding in ipairs({ "utf-8", "utf-16", "utf-32" }) do
    params_by_encoding[encoding] = vim.lsp.util.make_position_params(0, encoding)
  end

  ui.open_menu(state, lookup_id)

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
    results.sort(merged)
    state.all_items = merged
    if #merged > 0 then
      ui.apply_filters(state)
    elseif lsp_done and grep_done then
      ui.render_empty(state)
    end
  end

  lsp.collect(bufnr, params_by_encoding, function(items)
    vim.schedule(function()
      lsp_items = items
      lsp_done = true
      rebuild()
    end)
  end)

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
          local fname = vim.uri_to_fname(item.uri)
          local lnum = item.range.start.line + 1
          local col = item.range.start.character + 1
          item.kind = grep_classify.classify(fname, lnum, col, item.text)
          grep_items[#grep_items + 1] = item
        end
        rebuild()
      end, function(meta)
        if scan_id ~= grep_scan_id or not active_lookup() then
          return
        end
        meta = meta or {}
        local expand_limit = expanded_limit()
        meta.expanded = expanded
        meta.expand_limit = expand_limit
        meta.expandable = not expanded
          and meta.matches == true
          and expand_limit > (meta.match_limit or 0)
        grep_done = true
        state.result_meta = meta
        rebuild()
      end)
    end

    state.expand_results = function()
      local meta = state.result_meta
      if not active_lookup() or not meta or not meta.expandable then
        return
      end
      state.result_meta = nil
      run_grep(expanded_limit(), true)
    end

    run_grep(nil, false)
  else
    grep_done = true
  end
end

function M.setup(opts)
  config.setup(opts)
  state.opts = config.options
  setup_keymaps()
end

return M
