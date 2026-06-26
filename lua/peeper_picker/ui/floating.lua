local M = {}

local function apply_buf_options(buf, options)
  for option, value in pairs(options or {}) do
    vim.bo[buf][option] = value
  end
end

local hidden_search_groups = { "Search", "CurSearch", "IncSearch" }

local function suppress_search_winhighlight(value)
  local parts = {}
  if type(value) == "string" and value ~= "" then
    parts[#parts + 1] = value
  end
  for _, group in ipairs(hidden_search_groups) do
    parts[#parts + 1] = ("%s:PeeperPickerHiddenSearch"):format(group)
  end
  return table.concat(parts, ",")
end

local function apply_win_options(win, options)
  if not options then
    return
  end
  options = vim.tbl_extend("force", {}, options or {})
  options.winhighlight = suppress_search_winhighlight(options.winhighlight)
  for option, value in pairs(options or {}) do
    vim.wo[win][option] = value
  end
end

function M.win_config(spec)
  return {
    relative = "editor",
    width = spec.width,
    height = spec.height,
    row = spec.row,
    col = spec.col,
    style = "minimal",
    border = spec.border,
    title = spec.title,
    title_pos = spec.title_pos or "center",
    zindex = spec.zindex,
    focusable = spec.focusable,
  }
end

function M.create_buf(spec)
  spec = spec or {}
  local buf = vim.api.nvim_create_buf(false, true)
  if spec.name and spec.name ~= "" then
    vim.api.nvim_buf_set_name(buf, spec.name)
  end

  apply_buf_options(buf, {
    bufhidden = "wipe",
    buftype = "nofile",
    filetype = spec.filetype,
    modifiable = spec.modifiable,
    swapfile = false,
  })
  apply_buf_options(buf, spec.buf_options)
  return buf
end

function M.open(spec)
  spec = spec or {}
  local buf = M.create_buf(spec)
  local win = vim.api.nvim_open_win(buf, spec.enter ~= false, M.win_config(spec))
  apply_win_options(win, spec.win_options)
  return buf, win
end

function M.reconfigure(win, spec)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  vim.api.nvim_win_set_config(win, M.win_config(spec))
  apply_win_options(win, spec.win_options)
  return true
end

return M
