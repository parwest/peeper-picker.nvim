local M = {}

local paths = require("peeper_picker.paths")

local max_cached_lines = 20000

M.line_cache = {}
M.file_cache = {}

function M.reset()
  M.line_cache = {}
  M.file_cache = {}
end

local function loaded_buffer_lines(uri, first, last)
  local bufnr = vim.uri_to_bufnr(uri)
  if vim.fn.bufloaded(bufnr) == 1 then
    return vim.api.nvim_buf_get_lines(bufnr, first, last, false)
  end
end

local function read_file(uri)
  if M.file_cache[uri] then
    return M.file_cache[uri]
  end
  local ok, lines = pcall(vim.fn.readfile, vim.uri_to_fname(uri), "", max_cached_lines)
  if not ok then
    lines = {}
  end
  M.file_cache[uri] = lines
  return lines
end

local function read_lines(uri, first, last)
  local buffer_lines = loaded_buffer_lines(uri, first, last)
  if buffer_lines then
    return buffer_lines
  end

  local file = read_file(uri)
  local out = {}
  for lnum = first + 1, math.min(last, #file) do
    table.insert(out, file[lnum])
  end
  return out
end

function M.line_at(uri, lnum)
  local key = uri .. ":" .. lnum
  if M.line_cache[key] then
    return M.line_cache[key]
  end
  local lines = read_lines(uri, lnum, lnum + 1)
  local line = vim.trim(lines[1] or "")
  M.line_cache[key] = line
  return line
end

function M.context(item, context)
  local target = item.range.start.line
  local first = math.max(0, target - context)
  local last = target + context + 1
  local source = read_lines(item.uri, first, last)
  local width = #tostring(first + #source)
  local lines = {
    paths.display_uri(item.uri) .. ":" .. (target + 1) .. ":" .. (item.range.start.character + 1),
    "",
  }

  for idx, text in ipairs(source) do
    local lnum = first + idx
    local marker = lnum - 1 == target and ">" or " "
    table.insert(lines, ("%s %" .. width .. "d  %s"):format(marker, lnum, text))
  end

  return lines, target - first + 3
end

return M
