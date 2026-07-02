local M = {}

local floating = require("peeper_picker.ui.floating")
local keymap = require("peeper_picker.ui.keymap")

local FOOTER = " enter to peep · c clear · q to close "
local EMPTY_FOOTER = " q to close "
local ns = vim.api.nvim_create_namespace("peeper_picker_history_menu")
local sel_ns = vim.api.nvim_create_namespace("peeper_picker_history_sel")

-- default links so the menu themes itself; users can override either
local function ensure_highlights()
  local set = vim.api.nvim_set_hl
  set(0, "PeeperPickerHistoryName", { default = true, link = "Identifier" })
  set(0, "PeeperPickerHistorySelection", { default = true, link = "PmenuSel" })
end

local function close(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

function M.open(state, entries, on_pick, on_clear)
  ensure_highlights()
  local has_entries = #entries > 0
  local lines, targets = {}, {}
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = entry.name
    targets[#lines] =
      { bufnr = entry.bufnr, row = entry.row, col = entry.col, word = entry.name, text_only = entry.text_only }
  end
  if not has_entries then
    lines = { "No recent peeps" }
  end

  -- recomputed on open and on VimResized so the float stays centred and sized
  local footer = has_entries and FOOTER or EMPTY_FOOTER
  local function geometry()
    local width = vim.fn.strdisplaywidth(footer)
    for _, line in ipairs(lines) do
      width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
    end
    width = math.min(width, math.max(24, math.floor(vim.o.columns * 0.8)))
    local height = math.min(#lines, 15)
    return {
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      border = state.opts.border,
      title = " peeper history ",
      footer = footer,
      win_options = { cursorline = false, wrap = false },
    }
  end

  local spec = geometry()
  spec.filetype = "peeper-picker-history"
  spec.modifiable = true
  local buf, win = floating.open(spec)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if has_entries then
    for i, line in ipairs(lines) do
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
        end_col = #line,
        hl_group = "PeeperPickerHistoryName",
        priority = 100,
      })
    end
  end
  vim.bo[buf].modifiable = false

  -- selection is a chip over the name, and the cursor sits on column 0, so
  -- left/right do nothing and the highlight tracks the name itself
  local function refresh_selection()
    vim.api.nvim_buf_clear_namespace(buf, sel_ns, 0, -1)
    if not has_entries then
      return
    end
    local line = vim.api.nvim_win_get_cursor(win)[1]
    if vim.api.nvim_win_get_cursor(win)[2] ~= 0 then
      pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
    end
    vim.api.nvim_buf_set_extmark(buf, sel_ns, line - 1, 0, {
      end_col = #lines[line],
      hl_group = "PeeperPickerHistorySelection",
      priority = 200,
    })
  end

  vim.api.nvim_create_autocmd("CursorMoved", { buffer = buf, callback = refresh_selection })
  refresh_selection()

  local resize_group = vim.api.nvim_create_augroup("PeeperPickerHistoryResize", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = resize_group,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_del_augroup_by_id, resize_group)
        return
      end
      floating.reconfigure(win, geometry())
    end,
  })

  local function dismiss()
    pcall(vim.api.nvim_del_augroup_by_id, resize_group)
    close(win)
  end

  if has_entries then
    keymap.bind(buf, "n", "<CR>", function()
      local target = targets[vim.api.nvim_win_get_cursor(win)[1]]
      dismiss()
      if target then
        on_pick(target)
      end
    end)
    keymap.bind(buf, "n", "c", function()
      if vim.fn.confirm("Clear all peep history?", "&Yes\n&No", 2) == 1 then
        dismiss()
        if on_clear then
          on_clear()
        end
      end
    end)
  end
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    keymap.bind(buf, "n", lhs, dismiss)
  end
end

return M
