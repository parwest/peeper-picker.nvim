local M = {}

local paths = require("peeper_picker.paths")
local config = require("peeper_picker.config")

local uv = vim.uv or vim.loop

local builtin_ignored_dirs = {
  [".git"] = true,
  ["node_modules"] = true,
  [".next"] = true,
  ["dist"] = true,
  ["build"] = true,
  ["target"] = true,
  [".cache"] = true,
  [".venv"] = true,
}

local function ignored_dir_set()
  local set = {}
  for name in pairs(builtin_ignored_dirs) do
    set[name] = true
  end
  for _, name in ipairs(config.options.ignored_dirs or {}) do
    if type(name) == "string" and name ~= "" then
      set[name] = true
    end
  end
  return set
end

local binary_probe_bytes = 1024

local function is_binary(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return false
  end
  local chunk = uv.fs_read(fd, binary_probe_bytes, 0)
  uv.fs_close(fd)
  return chunk ~= nil and chunk:find("\0", 1, true) ~= nil
end

local dirs_per_tick = 64
local files_per_tick = 64
local max_matches = 5000
local max_files = 50000
local max_file_bytes = 1024 * 1024

local function scan_dir(dir, dir_stack, file_queue, ignored_dirs)
  local handle = uv.fs_scandir(dir)
  if not handle then
    return
  end
  while true do
    local name, typ = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local full = dir .. paths.separator() .. name
    if typ == nil then
      local stat = uv.fs_stat(full)
      typ = stat and stat.type or nil
    end
    if typ == "directory" then
      if not ignored_dirs[name] then
        dir_stack[#dir_stack + 1] = full
      end
    elseif typ == "file" then
      file_queue[#file_queue + 1] = full
    end
  end
end

function M.collect(opts, on_batch, on_done)
  local root = opts.root
  local word = opts.word
  if not root or not word or word == "" then
    on_done()
    return
  end

  -- whole-word match; pesc escapes magic chars in the symbol
  local pattern = "%f[%w_]" .. vim.pesc(word) .. "%f[^%w_]"
  local is_cancelled = opts.is_cancelled or function()
    return false
  end

  local ignored_dirs = ignored_dir_set()
  local match_limit = tonumber(opts.match_limit) or max_matches
  match_limit = math.max(1, math.floor(match_limit))
  local dir_stack = { root }
  local file_queue = {}
  local total_matches = 0
  local total_files = 0
  local match_work_remaining = false

  local overrides = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified and vim.bo[bufnr].buftype == "" then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        overrides[paths.normalize(name)] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      end
    end
  end
  local has_overrides = next(overrides) ~= nil
  local consumed = {}

  local function scan_line(file, lnum, line, batch)
    local from = 1
    while total_matches < match_limit do
      local col = line:find(pattern, from)
      if not col then
        break
      end
      batch[#batch + 1] = {
        kind = "ref",
        uri = vim.uri_from_fname(file),
        range = { start = { line = lnum - 1, character = col - 1 } },
        text = vim.trim(line),
        position_encoding = "utf-8",
      }
      total_matches = total_matches + 1
      from = col + 1
      if total_matches >= match_limit and line:find(pattern, from) then
        match_work_remaining = true
      end
    end
  end

  local function scan_file_lines(file, lines, batch)
    for lnum, line in ipairs(lines) do
      if total_matches >= match_limit then
        match_work_remaining = true
        break
      end
      if line:find(pattern) then
        scan_line(file, lnum, line, batch)
      end
    end
  end

  local function flush_overrides(batch)
    for path, lines in pairs(overrides) do
      if not consumed[path] and paths.is_inside(path, root) then
        if total_matches >= match_limit then
          match_work_remaining = true
          break
        end
        consumed[path] = true
        scan_file_lines(path, lines, batch)
      end
    end
  end

  local function done()
    return total_matches >= match_limit or total_files >= max_files or (#dir_stack == 0 and #file_queue == 0)
  end

  local function step()
    if is_cancelled() then
      return
    end

    local dirs_done = 0
    while #dir_stack > 0 and dirs_done < dirs_per_tick do
      scan_dir(table.remove(dir_stack), dir_stack, file_queue, ignored_dirs)
      dirs_done = dirs_done + 1
    end

    local batch = {}
    local files_done = 0
    while #file_queue > 0 and files_done < files_per_tick and total_matches < match_limit and total_files < max_files do
      local file = table.remove(file_queue)
      files_done = files_done + 1
      total_files = total_files + 1
      local override = has_overrides and overrides[paths.normalize(file)] or nil
      if override then
        consumed[paths.normalize(file)] = true
        scan_file_lines(file, override, batch)
      else
        local stat = uv.fs_stat(file)
        if stat and stat.size <= max_file_bytes and not is_binary(file) then
          local ok, lines = pcall(vim.fn.readfile, file)
          if ok then
            scan_file_lines(file, lines, batch)
          end
        end
      end
    end

    if done() and has_overrides then
      flush_overrides(batch)
    end

    if #batch > 0 then
      on_batch(batch)
    end

    if done() or is_cancelled() then
      local pending_work = #file_queue > 0 or #dir_stack > 0
      on_done({
        matches = total_matches >= match_limit and (pending_work or match_work_remaining),
        files = total_files >= max_files and pending_work,
        match_limit = match_limit,
        file_limit = max_files,
      })
    else
      -- defer via timer; chained vim.schedule callbacks starve the event loop
      vim.defer_fn(step, 1)
    end
  end

  vim.defer_fn(step, 1)
end

return M
