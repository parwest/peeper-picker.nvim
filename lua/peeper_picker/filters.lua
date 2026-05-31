local M = {}

local paths = require("peeper_picker.paths")
local results = require("peeper_picker.results")

function M.defaults()
  return {
    scope = "workspace",
    kind_mode = "both",
    path = "",
    extension = "",
  }
end

function M.match(item, filters, source)
  if filters.kind_mode == "refs" and item.kind ~= "ref" then
    return false
  end
  if filters.kind_mode == "defs" and item.kind == "ref" then
    return false
  end

  local item_path = paths.normalize(vim.uri_to_fname(item.uri))
  if filters.scope == "workspace" then
    if source.workspace_root and source.workspace_root ~= "" and not paths.is_inside(item_path, source.workspace_root) then
      return false
    end
  elseif filters.scope == "file" then
    if not source.path or item_path ~= source.path then
      return false
    end
  elseif filters.scope == "dir" then
    if not source.dir or not paths.is_inside(item_path, source.dir) then
      return false
    end
  end

  if filters.path ~= "" and not paths.display_uri(item.uri):lower():find(filters.path, 1, true) then
    return false
  end

  if filters.extension ~= "" then
    local ext = paths.normalize_extension(filters.extension)
    if ext ~= "" and paths.display_uri(item.uri):lower():sub(-#ext) ~= ext then
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

function M.kind_label(mode)
  return mode == "refs" and "refs" or mode == "defs" and "defs" or "both"
end

function M.extension_label(value)
  local ext = paths.normalize_extension(value)
  return ext ~= "" and ext or "any"
end

function M.field_label(value)
  return value ~= "" and value or "any"
end

function M.item_key(item)
  return results.key(item)
end

return M
