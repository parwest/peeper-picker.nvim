local M = {}

local config = require("peeper_picker.config")

local ns = vim.api.nvim_create_namespace("peeper_picker_history")
local entries = {}

local function cap()
  local n = tonumber(config.options.history_size)
  if not n then
    return config.defaults.history_size
  end
  return math.max(0, math.floor(n))
end

-- start byte (0-based) and text of the identifier covering the byte column on the
-- given row (both 0-based), or nil when the column is not on an identifier. uses
-- the buffer's own iskeyword (via \k) so language-specific identifier characters
-- (e.g. ruby `?`/`!`, lisp/css `-`, accented unicode) are kept whole — and match
-- what the peep recorded, so an unchanged symbol never looks renamed
local function identifier(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line or line == "" then
    return nil
  end
  local found = vim.api.nvim_buf_call(bufnr, function()
    local re = vim.regex([[\k\+]])
    local from = 0
    while from <= #line do
      local ms, me = re:match_str(line:sub(from + 1))
      if not ms then
        return nil
      end
      local s, e = from + ms, from + me
      if col >= s and col < e then
        return { s, line:sub(s + 1, e) }
      end
      from = e
    end
    return nil
  end)
  if not found then
    return nil
  end
  return found[1], found[2]
end

local function word_at(bufnr, row, col)
  return select(2, identifier(bufnr, row, col)) or ""
end

local function drop(index)
  local entry = entries[index]
  if not entry then
    return
  end
  if vim.api.nvim_buf_is_valid(entry.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, ns, entry.extmark)
  end
  table.remove(entries, index)
end

-- current anchor position, or nil if the buffer or extmark is gone
local function locate(entry)
  if not vim.api.nvim_buf_is_valid(entry.bufnr) or not vim.api.nvim_buf_is_loaded(entry.bufnr) then
    return nil
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(entry.bufnr, ns, entry.extmark, {})
  if not pos or not pos[1] then
    return nil
  end
  return pos[1], pos[2]
end

function M.record(bufnr, row, col, word)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) or not word or word == "" then
    return
  end
  -- anchor to the start of the identifier so the anchor sits on the word itself
  local start = identifier(bufnr, row, col)
  if start then
    col = start
  end
  -- one entry per name: a repeat peep of the same name drops the old entry and
  -- re-adds it at the front with a fresh anchor at the spot you just peeped from
  for i = #entries, 1, -1 do
    if entries[i].name == word then
      drop(i)
    end
  end
  -- left gravity pins the anchor to the start of the identifier, so an in-place
  -- rename leaves it reading the new word rather than drifting to the line end
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, col, { right_gravity = false })
  if not ok then
    return
  end
  table.insert(entries, 1, { bufnr = bufnr, extmark = id, name = word })
  while #entries > cap() do
    drop(#entries)
  end
end

-- view-models for the menu, newest first, pruning anything whose anchor is gone.
-- each entry is a name you peeped, frozen as you peeked it. `text_only` is set when
-- that name no longer lives at its anchor (it was renamed away) — peeping it then
-- greps the name for stragglers instead of resolving the live symbol.
function M.list()
  local out = {}
  local i = 1
  while i <= #entries do
    local entry = entries[i]
    local row, col = locate(entry)
    if not row then
      drop(i)
    else
      out[#out + 1] = {
        bufnr = entry.bufnr,
        row = row,
        col = col,
        name = entry.name,
        text_only = word_at(entry.bufnr, row, col) ~= entry.name,
      }
      i = i + 1
    end
  end
  return out
end

function M.clear()
  for i = #entries, 1, -1 do
    drop(i)
  end
end

return M
