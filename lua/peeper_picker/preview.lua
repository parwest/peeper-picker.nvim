local M = {}

local max_cached_total_lines = 20000
local max_cached_files = 64
local max_cached_line_entries = 4096

M.line_cache = {}
M.line_cache_count = 0
M.file_cache = {}
M.file_cache_count = 0
M.file_cache_line_count = 0

function M.reset()
  M.line_cache = {}
  M.line_cache_count = 0
  M.file_cache = {}
  M.file_cache_count = 0
  M.file_cache_line_count = 0
end

local function loaded_buffer_lines(uri, first, last)
  local bufnr = vim.fn.bufnr(vim.uri_to_fname(uri), false)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, first, last, false)
  end
end

local function read_file(uri)
  if M.file_cache[uri] then
    return M.file_cache[uri]
  end
  local ok, lines = pcall(vim.fn.readfile, vim.uri_to_fname(uri))
  if not ok then
    lines = {}
  end
  if M.file_cache_count >= max_cached_files or M.file_cache_line_count + #lines > max_cached_total_lines then
    M.file_cache = {}
    M.file_cache_count = 0
    M.file_cache_line_count = 0
  end
  M.file_cache[uri] = lines
  M.file_cache_count = M.file_cache_count + 1
  M.file_cache_line_count = M.file_cache_line_count + #lines
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

function M.raw_line_at(uri, lnum)
  local key = uri .. ":" .. lnum
  if M.line_cache[key] ~= nil then
    return M.line_cache[key]
  end
  local lines = read_lines(uri, lnum, lnum + 1)
  local line = lines[1]
  if M.line_cache_count >= max_cached_line_entries then
    M.line_cache = {}
    M.line_cache_count = 0
  end
  M.line_cache[key] = line
  M.line_cache_count = M.line_cache_count + 1
  return line
end

function M.line_at(uri, lnum)
  return vim.trim(M.raw_line_at(uri, lnum) or "")
end

function M.context(item, context)
  local target = item.range.start.line
  local first = math.max(0, target - context)
  local last = target + context + 1
  local source = read_lines(item.uri, first, last)
  return source, target - first + 1, first + 1
end

return M
