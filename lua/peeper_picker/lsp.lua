local M = {}

local results = require("peeper_picker.results")

local methods = {
  decl = "textDocument/declaration",
  def = "textDocument/definition",
  ref = "textDocument/references",
}

M.methods = methods

local function client_position_params(client, bufnr, params_by_encoding)
  local encoding = client.offset_encoding or "utf-16"
  local params = vim.deepcopy(params_by_encoding[encoding] or params_by_encoding["utf-16"])
  params.textDocument.uri = vim.uri_from_bufnr(bufnr)
  return params, encoding
end

local function request_all(bufnr, method, make_params, callback)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  if #clients == 0 then
    callback({})
    return
  end

  local locations = {}
  local pending = #clients
  for _, client in ipairs(clients) do
    local params, encoding = make_params(client)
    local ok = client:request(method, params, function(_, result)
      if result then
        for _, location in ipairs(results.flatten(result)) do
          table.insert(locations, { location = location, encoding = encoding })
        end
      end
      pending = pending - 1
      if pending == 0 then
        callback(locations)
      end
    end, bufnr)
    if not ok then
      pending = pending - 1
      if pending == 0 then
        callback(locations)
      end
    end
  end
end

function M.supported_count(bufnr)
  local count = 0
  for _, method in pairs(methods) do
    if #vim.lsp.get_clients({ bufnr = bufnr, method = method }) > 0 then
      count = count + 1
    end
  end
  return count
end

function M.collect(bufnr, params_by_encoding, on_done)
  local items, seen = {}, {}
  local pending = M.supported_count(bufnr)

  local function finish()
    pending = pending - 1
    if pending > 0 then
      return
    end
    results.sort(items)
    on_done(items)
  end

  if #vim.lsp.get_clients({ bufnr = bufnr, method = methods.decl }) > 0 then
    request_all(bufnr, methods.decl, function(client)
      return client_position_params(client, bufnr, params_by_encoding)
    end, function(locations)
      for _, entry in ipairs(locations) do
        results.add(items, seen, entry.location, "decl", entry.encoding)
      end
      finish()
    end)
  end

  if #vim.lsp.get_clients({ bufnr = bufnr, method = methods.def }) > 0 then
    request_all(bufnr, methods.def, function(client)
      return client_position_params(client, bufnr, params_by_encoding)
    end, function(locations)
      for _, entry in ipairs(locations) do
        results.add(items, seen, entry.location, "def", entry.encoding)
      end
      finish()
    end)
  end

  if #vim.lsp.get_clients({ bufnr = bufnr, method = methods.ref }) > 0 then
    request_all(bufnr, methods.ref, function(client)
      local ref_params, encoding = client_position_params(client, bufnr, params_by_encoding)
      ref_params.context = { includeDeclaration = true }
      return ref_params, encoding
    end, function(locations)
      for _, entry in ipairs(locations) do
        results.add(items, seen, entry.location, "ref", entry.encoding)
      end
      finish()
    end)
  end
end

return M
