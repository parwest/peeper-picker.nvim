local M = {}

local config = require("peeper_picker.config")
local filters = require("peeper_picker.filters")
local lsp = require("peeper_picker.lsp")
local paths = require("peeper_picker.paths")
local preview = require("peeper_picker.preview")
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
  state.lookup_id = state.lookup_id + 1
  local lookup_id = state.lookup_id

  if lsp.supported_count(bufnr) == 0 then
    ui.close_menu(state)
    vim.notify("peeper-picker.nvim: no supported LSP definition/reference methods", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_path = vim.api.nvim_buf_get_name(bufnr)
  current_path = current_path ~= "" and paths.normalize(current_path) or nil
  state.opts = config.options
  state.filters = filters.defaults()
  state.source = {
    path = current_path,
    dir = current_path and paths.normalize(vim.fn.fnamemodify(current_path, ":p:h")) or nil,
    workspace_root = paths.workspace_root(bufnr, current_path),
    filetype = vim.bo[bufnr].filetype,
    word = vim.fn.expand("<cword>"),
    line = cursor[1],
    character = cursor[2] + 1,
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

  lsp.collect(bufnr, params_by_encoding, function(items)
    vim.schedule(function()
      if not active_lookup() then
        return
      end
      if #items == 0 then
        ui.render_empty(state)
      else
        state.all_items = items
        ui.apply_filters(state)
      end
    end)
  end)
end

function M.setup(opts)
  config.setup(opts)
  state.opts = config.options
  vim.api.nvim_create_user_command("PeeperPicker", M.find, { force = true })
  setup_keymaps()
end

return M
