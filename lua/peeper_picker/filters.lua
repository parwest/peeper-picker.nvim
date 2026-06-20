local M = {}

local paths = require("peeper_picker.paths")
local config = require("peeper_picker.config")

local result_filter_aliases = {
  all = "all",
  code = "code",
  refs = "refs",
  references = "refs",
  defs = "defs",
  definitions = "defs",
}

function M.default_result_mode()
  local configured = config.options.default_result_filtering
  return result_filter_aliases[tostring(configured or "all"):lower()] or "all"
end

function M.defaults()
  local filters = {
    scope = "workspace",
    kind_mode = "both",
    match_mode = "code",
    path = "",
    extension = "",
  }
  M.set_result_mode(filters, M.default_result_mode())
  return filters
end

local function path_matches(item_path, uri, needle, source)
  local workspace_relative = source and source.workspace_root and paths.relative_to(item_path, source.workspace_root)
  local candidates = {}
  if workspace_relative and workspace_relative ~= "" then
    candidates[#candidates + 1] = workspace_relative
  else
    candidates[#candidates + 1] = paths.display_uri(uri)
    candidates[#candidates + 1] = item_path
  end

  for _, candidate in ipairs(candidates) do
    if candidate:lower():find(needle, 1, true) then
      return true
    end
  end
  return false
end

local function path_query(value)
  local query = vim.trim(value or ""):lower()
  if query:sub(1, 1) ~= "!" then
    return query, false
  end
  return vim.trim(query:sub(2)), true
end

local function extension_query(value)
  local query = vim.trim(value or ""):lower()
  local exclude = query:sub(1, 1) == "!"
  if exclude then
    query = vim.trim(query:sub(2))
  end
  return paths.normalize_extension(query), exclude
end

function M.match(item, filters, source)
  local is_definition = item.kind == "def" or item.kind == "decl"
  local is_extra_match = item.kind == "txt" or item.kind == "com"

  if (filters.match_mode or "code") ~= "all" and is_extra_match then
    return false
  end

  if filters.kind_mode == "refs" and is_definition then
    return false
  end
  if filters.kind_mode == "defs" and not is_definition then
    return false
  end

  local item_path = paths.normalize(vim.uri_to_fname(item.uri))
  if filters.scope == "workspace" then
  elseif filters.scope == "file" then
    if not source.path or item_path ~= source.path then
      return false
    end
  elseif filters.scope == "dir" then
    if not source.dir or not paths.is_inside(item_path, source.dir) then
      return false
    end
  end

  local path_filter, exclude_path = path_query(filters.path)
  if path_filter ~= "" then
    local matched_path = path_matches(item_path, item.uri, path_filter, source)
    if exclude_path and matched_path then
      return false
    end
    if not exclude_path and not matched_path then
      return false
    end
  end

  local ext, exclude_ext = extension_query(filters.extension)
  if ext ~= "" then
    local matched_ext = paths.display_uri(item.uri):lower():sub(-#ext) == ext
    if exclude_ext and matched_ext then
      return false
    end
    if not exclude_ext and not matched_ext then
      return false
    end
  end

  return true
end

function M.apply(items, filters, source)
  local filtered = {}
  for _, item in ipairs(items or {}) do
    if M.match(item, filters, source) then
      table.insert(filtered, item)
    end
  end
  return filtered
end

function M.scope_hint(source)
  if source.workspace_root then
    return "workspace: " .. paths.display_path(source.workspace_root)
  end
  return "workspace follows the editor cwd"
end

function M.scope_label(scope)
  return scope == "file" and "file" or scope == "dir" and "dir" or "workspace"
end

function M.result_mode(filters)
  filters = filters or {}
  if filters.kind_mode == "refs" then
    return "refs"
  end
  if filters.kind_mode == "defs" then
    return "defs"
  end
  if filters.match_mode == "all" then
    return "all"
  end
  return "code"
end

function M.result_label(filters)
  return M.result_mode(filters)
end

function M.set_result_mode(filters, mode)
  if mode == "refs" then
    filters.kind_mode = "refs"
    filters.match_mode = "code"
  elseif mode == "defs" then
    filters.kind_mode = "defs"
    filters.match_mode = "code"
  elseif mode == "all" then
    filters.kind_mode = "both"
    filters.match_mode = "all"
  else
    filters.kind_mode = "both"
    filters.match_mode = "code"
  end
end

function M.extension_label(value)
  local ext, exclude_ext = extension_query(value)
  if ext == "" then
    return "any"
  end
  return exclude_ext and ("excluding " .. ext) or ("matching " .. ext)
end

function M.field_label(value)
  return value ~= "" and value or "any"
end

function M.path_label(value)
  local path_filter, exclude_path = path_query(value)
  if path_filter == "" then
    return "any"
  end
  return exclude_path and ("excluding " .. path_filter) or ("containing " .. path_filter)
end

return M
