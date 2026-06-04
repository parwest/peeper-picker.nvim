local M = {}

local paths = require("peeper_picker.paths")
local config = require("peeper_picker.config")

local uv = vim.uv or vim.loop

-- Directories we never descend into during a text search. Users can extend this
-- (never shrink it) via the `ignored_dirs` config option.
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

-- Merge the built-in ignore set with any user-configured directory names. The
-- built-ins are always present; the config list is purely additive.
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

-- Cheap binary sniff: read the file's head and treat it as binary if it
-- contains a NUL byte. Skips minified blobs/images/lockfiles before the much
-- more expensive whole-file readfile + pattern scan.
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

local dirs_per_tick = 64 -- directories enumerated per scheduled tick
local files_per_tick = 64 -- files read+scanned per scheduled tick
local max_matches = 5000 -- safety cap on total results
local max_files = 50000 -- safety cap on files scanned (bounds worst-case walks)
local max_file_bytes = 1024 * 1024 -- skip files larger than 1MB (likely generated/binary)

-- Enumerate a single directory's immediate entries, pushing subdirectories onto
-- `dir_stack` (skipping ignored ones) and files onto `file_queue`. Reading one
-- directory is bounded by its entry count, so this never blocks for long.
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
      -- Some filesystems don't report a type; fall back to a stat.
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

-- Stream every whole-word textual match of `opts.word` under `opts.root`.
--   on_batch(items) is called repeatedly with new items as they are found.
--   on_done()       is called once when the scan finishes (or is capped).
-- opts.is_cancelled() is polled every tick so a stale/closed lookup stops work.
--
-- Both the directory walk and the file reads happen incrementally inside
-- scheduled ticks, so nothing blocks the UI synchronously regardless of tree
-- size, and a word with zero matches can't lock up a large workspace.
function M.collect(opts, on_batch, on_done)
  local root = opts.root
  local word = opts.word
  if not root or not word or word == "" then
    on_done()
    return
  end

  -- Whole-word match using Lua frontier patterns; escape the symbol so names
  -- with magic characters are treated literally.
  local pattern = "%f[%w_]" .. vim.pesc(word) .. "%f[^%w_]"
  local is_cancelled = opts.is_cancelled or function()
    return false
  end

  local ignored_dirs = ignored_dir_set()
  local dir_stack = { root }
  local file_queue = {}
  local total_matches = 0
  local total_files = 0

  local function scan_line(file, lnum, line, batch)
    local from = 1
    while total_matches < max_matches do
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
    end
  end

  local function done()
    return total_matches >= max_matches or total_files >= max_files or (#dir_stack == 0 and #file_queue == 0)
  end

  local function step()
    if is_cancelled() then
      return
    end

    -- Phase 1: enumerate a bounded number of directories to refill the queue.
    local dirs_done = 0
    while #dir_stack > 0 and dirs_done < dirs_per_tick do
      scan_dir(table.remove(dir_stack), dir_stack, file_queue, ignored_dirs)
      dirs_done = dirs_done + 1
    end

    -- Phase 2: read+scan a bounded number of queued files.
    local batch = {}
    local files_done = 0
    while #file_queue > 0 and files_done < files_per_tick and total_matches < max_matches and total_files < max_files do
      local file = table.remove(file_queue)
      files_done = files_done + 1
      total_files = total_files + 1
      local stat = uv.fs_stat(file)
      if stat and stat.size <= max_file_bytes and not is_binary(file) then
        local ok, lines = pcall(vim.fn.readfile, file)
        if ok then
          for lnum, line in ipairs(lines) do
            if total_matches >= max_matches then
              break
            end
            if line:find(pattern) then
              scan_line(file, lnum, line, batch)
            end
          end
        end
      end
    end

    if #batch > 0 then
      on_batch(batch)
    end

    if done() or is_cancelled() then
      on_done()
    else
      -- Yield through a timer rather than vim.schedule: chained schedule
      -- callbacks drain back-to-back and starve the event loop (freezing input
      -- on large trees). A tiny defer returns control to the UI between ticks.
      vim.defer_fn(step, 1)
    end
  end

  vim.defer_fn(step, 1)
end

return M
