local M = {}

local paths = require("peeper_picker.paths")
local config = require("peeper_picker.config")
local grep_classify = require("peeper_picker.grep_classify")

local uv = vim.uv

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

local dirs_per_tick = 64
local max_matches = 5000
local max_files = 50000
local max_file_bytes = 1024 * 1024
local max_file_lines_per_tick = 1024
local max_file_matches_per_tick = 1024

local function option_int(name)
  local value = tonumber(config.options[name]) or tonumber(config.defaults[name])
  return math.max(1, math.floor(value))
end

local function read_text_lines(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  if not stat or stat.type ~= "file" or stat.size > max_file_bytes then
    uv.fs_close(fd)
    return nil
  end
  local data = stat.size > 0 and uv.fs_read(fd, stat.size, 0) or ""
  uv.fs_close(fd)
  if not data or data:sub(1, binary_probe_bytes):find("\0", 1, true) then
    return nil
  end
  local lines = vim.split(data, "\n", { plain = true })
  for i, line in ipairs(lines) do
    if line:sub(-1) == "\r" then
      lines[i] = line:sub(1, -2)
    end
  end
  return lines, data
end

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

  local word_regex = vim.regex([[\C\V\<]] .. word:gsub([[\]], [[\\]]) .. [[\>]])
  local is_cancelled = opts.is_cancelled or function()
    return false
  end

  local ignored_dirs = ignored_dir_set()
  local match_limit = tonumber(opts.match_limit) or max_matches
  match_limit = math.max(1, math.floor(match_limit))
  local scan_files_per_tick = option_int("scan_files_per_tick")
  local classify_limit_per_tick = option_int("classify_files_per_tick")
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
  local override_queue = {}
  if has_overrides then
    for path, lines in pairs(overrides) do
      if paths.is_inside(path, root) then
        override_queue[#override_queue + 1] = { file = path, lines = lines }
      end
    end
  end
  local current_file = nil

  local function file_state(file, lines, source)
    if not lines then
      lines, source = read_text_lines(file)
    end
    if not lines then
      return nil
    end
    return {
      file = file,
      lines = lines,
      source = source,
      line_index = 1,
      line_from = 1,
      classifier = nil,
    }
  end

  local function classify_matches(state, batch, first, last)
    if last < first then
      return
    end
    if not state.classifier then
      state.classifier = grep_classify.classifier(state.file, state.source)
    end
    state.classifier(batch, first, last)
  end

  local function finish_line(state)
    state.line_index = state.line_index + 1
    state.line_from = 1
  end

  local function scan_current_file(batch)
    local state = current_file
    if not state then
      return true, false
    end

    local first_match = #batch + 1
    local lines_done = 0
    local matches_done = 0
    while
      state.line_index <= #state.lines
      and total_matches < match_limit
      and lines_done < max_file_lines_per_tick
      and matches_done < max_file_matches_per_tick
    do
      local line = state.lines[state.line_index] or ""
      local from = state.line_from or 1
      if from > #line or not line:find(word, from, true) then
        finish_line(state)
        lines_done = lines_done + 1
      else
        local match_start, match_end = word_regex:match_str(line:sub(from))
        if not match_start then
          finish_line(state)
          lines_done = lines_done + 1
        else
          local col = from + match_start
          batch[#batch + 1] = {
            kind = "ref",
            uri = vim.uri_from_fname(state.file),
            range = { start = { line = state.line_index - 1, character = col - 1 } },
            text = vim.trim(line),
            position_encoding = "utf-8",
          }
          total_matches = total_matches + 1
          matches_done = matches_done + 1
          state.line_from = from + match_end
          if total_matches >= match_limit then
            match_work_remaining = state.line_index < #state.lines
              or word_regex:match_str(line:sub(state.line_from)) ~= nil
          end
        end
      end
    end

    local last_match = #batch
    classify_matches(state, batch, first_match, last_match)
    return state.line_index > #state.lines or total_matches >= match_limit, last_match >= first_match
  end

  local function done()
    return total_matches >= match_limit
      or total_files >= max_files
      or (not current_file and #override_queue == 0 and #dir_stack == 0 and #file_queue == 0)
  end

  local function step()
    if is_cancelled() then
      return
    end

    local batch = {}

    local files_done = 0
    local classified_files = 0
    local should_yield = false

    if current_file then
      local finished, matched = scan_current_file(batch)
      if matched then
        classified_files = classified_files + 1
      end
      if finished then
        current_file = nil
      else
        should_yield = true
      end
    end

    -- scan modified buffers first so unsaved edits are never starved by the match cap
    while
      not should_yield
      and #override_queue > 0
      and total_matches < match_limit
      and classified_files < classify_limit_per_tick
    do
      local override = table.remove(override_queue)
      current_file = file_state(override.file, override.lines)
      local finished, matched = scan_current_file(batch)
      if matched then
        classified_files = classified_files + 1
      end
      if finished then
        current_file = nil
      else
        should_yield = true
      end
    end

    local dirs_done = 0
    while not should_yield and #dir_stack > 0 and dirs_done < dirs_per_tick do
      scan_dir(table.remove(dir_stack), dir_stack, file_queue, ignored_dirs)
      dirs_done = dirs_done + 1
    end

    while
      not should_yield
      and #file_queue > 0
      and files_done < scan_files_per_tick
      and total_matches < match_limit
      and total_files < max_files
      and classified_files < classify_limit_per_tick
    do
      local file = table.remove(file_queue)
      files_done = files_done + 1
      total_files = total_files + 1
      local norm = has_overrides and paths.normalize(file) or nil
      local override = norm and overrides[norm] or nil
      if not override then
        current_file = file_state(file)
        if current_file then
          local finished, matched = scan_current_file(batch)
          if matched then
            classified_files = classified_files + 1
          end
          if finished then
            current_file = nil
          else
            should_yield = true
          end
        end
      end
    end

    if #batch > 0 then
      on_batch(batch)
    end

    if done() or is_cancelled() then
      local pending_work = current_file ~= nil or #override_queue > 0 or #file_queue > 0 or #dir_stack > 0
      on_done({
        matches = total_matches >= match_limit and (pending_work or match_work_remaining),
        files = total_files >= max_files and pending_work,
        match_limit = match_limit,
      })
    else
      -- defer with a timer because chained schedule callbacks starve the event loop
      vim.defer_fn(step, 1)
    end
  end

  vim.defer_fn(step, 1)
end

return M
