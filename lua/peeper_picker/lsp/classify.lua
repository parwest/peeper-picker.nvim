local M = {}

local role_priority = {
  ["parameter"] = 100,
  ["type parameter"] = 98,
  ["property"] = 95,
  ["field"] = 94,
  ["method"] = 91,
  ["function"] = 90,
  ["constructor"] = 88,
  ["class"] = 85,
  ["interface"] = 84,
  ["struct"] = 84,
  ["enum"] = 84,
  ["enum member"] = 83,
  ["type"] = 82,
  ["module"] = 80,
  ["namespace"] = 80,
  ["package"] = 80,
  ["constant"] = 75,
  ["key"] = 74,
  ["variable"] = 70,
  ["event"] = 68,
  ["macro"] = 68,
  ["decorator"] = 68,
  ["symbol"] = 0,
}

local declaration_node_kinds = {
  annotation = "decorator",
  arrow_function = "function",
  class_declaration = "class",
  class_definition = "class",
  class_specifier = "class",
  closure_expression = "function",
  constant_declaration = "constant",
  constant_item = "constant",
  constructor_declaration = "constructor",
  decorator = "decorator",
  enum_declaration = "enum",
  enum_member = "enum member",
  enum_specifier = "enum",
  enum_variant = "enum member",
  event_declaration = "event",
  field_declaration = "field",
  field_definition = "field",
  field_identifier = "field",
  formal_parameter = "parameter",
  function_declaration = "function",
  function_definition = "function",
  function_expression = "function",
  function_item = "function",
  function_signature_item = "function",
  function_statement = "function",
  interface_declaration = "interface",
  lambda_expression = "function",
  macro_definition = "macro",
  method_declaration = "method",
  method_definition = "method",
  method_signature = "method",
  module_declaration = "module",
  named_parameter = "parameter",
  namespace_declaration = "namespace",
  optional_parameter = "parameter",
  package_declaration = "package",
  parameter = "parameter",
  parameter_declaration = "parameter",
  property_declaration = "property",
  property_identifier = "property",
  property_signature = "property",
  required_parameter = "parameter",
  scoped_type_identifier = "type",
  struct_declaration = "struct",
  struct_item = "struct",
  trait_item = "interface",
  type_alias_declaration = "type",
  type_declaration = "type",
  type_identifier = "type",
  type_parameter = "type parameter",
  type_parameter_declaration = "type parameter",
  variable_declaration = "variable",
  variable_declarator = "variable",
}

local function normalize_kind_label(value)
  if not value or value == "" then
    return nil
  end

  local label = tostring(value):gsub("([a-z0-9])([A-Z])", "%1 %2")
  label = label:gsub("[-_]+", " ")
  label = label:lower()
  label = label:gsub("%s+", " ")
  return vim.trim(label)
end

local function kind_rank(kind)
  return role_priority[kind or "symbol"] or 0
end

local function choose_better_kind(current, candidate)
  candidate = normalize_kind_label(candidate)
  current = normalize_kind_label(current)

  if not candidate or candidate == "" then
    return current
  end
  if not current or current == "" then
    return candidate
  end

  local current_rank = kind_rank(current)
  local candidate_rank = kind_rank(candidate)
  if candidate_rank > current_rank then
    return candidate
  end
  return current
end

local function type_matches(node_type, fragments)
  if not node_type then
    return false
  end
  for _, fragment in ipairs(fragments or {}) do
    if node_type:find(fragment, 1, true) then
      return true
    end
  end
  return false
end

local function has_matching_ancestor(node, fragments, max_depth)
  local current = node
  for _ = 1, (max_depth or 8) do
    if not current then
      break
    end
    if type_matches(current:type(), fragments) then
      return true
    end
    current = current:parent()
  end
  return false
end

local type_fragments = {
  "type_identifier", "scoped_type_identifier", "type_annotation", "qualified_type",
  "generic_type", "type_reference", "type_ref", "named_type", "type_name",
  "supertype", "implements", "extends",
}

local fuzzy_roles = {
  { { "enum_member", "enummember", "variant" }, "enum member" },
  { { "type_parameter", "typeparameter" }, "type parameter" },
  { { "property" }, "property" },
  { { "field" }, "field" },
  { { "parameter" }, "parameter" },
  { { "method" }, "method" },
  { { "function", "lambda", "closure", "arrow" }, "function" },
  { { "class" }, "class" },
  { { "interface", "trait" }, "interface" },
  { { "struct" }, "struct" },
  { { "enum" }, "enum" },
  { { "module", "mod" }, "module" },
  { { "namespace" }, "namespace" },
  { { "package" }, "package" },
  { { "constructor" }, "constructor" },
  { { "constant", "const" }, "constant" },
  { { "event" }, "event" },
  { { "macro" }, "macro" },
  { { "decorator", "annotation" }, "decorator" },
  { { "variable", "binding", "declarator", "let", "var" }, "variable" },
  { type_fragments, "type" },
}

local function role_from_node_type(node_type)
  if not node_type then
    return nil
  end

  local exact = declaration_node_kinds[node_type]
  if exact then
    return exact
  end

  for _, entry in ipairs(fuzzy_roles) do
    if type_matches(node_type, entry[1]) then
      return entry[2]
    end
  end

  return nil
end

local function semantic_token_symbol(bufnr, cursor, word)
  if not vim.lsp.semantic_tokens or not vim.lsp.semantic_tokens.get_at_pos then
    return nil
  end

  local ok, tokens = pcall(vim.lsp.semantic_tokens.get_at_pos, bufnr, cursor[1] - 1, cursor[2])
  if not ok or type(tokens) ~= "table" then
    return nil
  end

  local best_kind = nil
  local best_span = math.huge
  for _, token in ipairs(tokens) do
    local kind = normalize_kind_label(token.type)
    if kind and kind_rank(kind) > 0 then
      local span = ((token.end_line - token.line) * 100000) + (token.end_col - token.start_col)
      if not best_kind or kind_rank(kind) > kind_rank(best_kind) or (kind_rank(kind) == kind_rank(best_kind) and span < best_span) then
        best_kind = kind
        best_span = span
      end
    end
  end

  if not best_kind then
    return nil
  end

  return {
    kind = best_kind,
    name = word,
  }
end

local function treesitter_source_symbol(bufnr, cursor, word)
  if not word or word == "" or not vim.treesitter or not vim.treesitter.get_node then
    return nil
  end

  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { cursor[1] - 1, cursor[2] } })
  if not ok or not node then
    return nil
  end

  local function parent_type(n)
    local parent = n and n:parent()
    return parent, parent and parent:type() or nil
  end

  local current = node
  for _ = 1, 8 do
    local node_type = current:type()
    local parent, parent_node_type = parent_type(current)
    local _, grandparent_node_type = parent_type(parent)

    if node_type == "property_identifier" or node_type == "field_identifier" then
      if grandparent_node_type and (type_matches(grandparent_node_type, { "call", "invoke" }) or type_matches(parent_node_type, { "method" })) then
        return { kind = "method", name = word }
      end
      return { kind = node_type == "field_identifier" and "field" or "property", name = word }
    end

    if node_type == "identifier" then
      if has_matching_ancestor(current, { "parameter" }) then
        return { kind = "parameter", name = word }
      end
      if has_matching_ancestor(current, { "type_parameter", "typeparameter" }) then
        return { kind = "type parameter", name = word }
      end
      if has_matching_ancestor(current, type_fragments) then
        return { kind = "type", name = word }
      end
      if parent_node_type and type_matches(parent_node_type, { "call", "invoke" }) then
        if grandparent_node_type and (type_matches(grandparent_node_type, { "member", "field", "property" }) or type_matches(parent_node_type, { "method" })) then
          return { kind = "method", name = word }
        end
        return { kind = "function", name = word }
      end
      if parent_node_type and type_matches(parent_node_type, { "member", "field", "property", "access" }) then
        if grandparent_node_type and type_matches(grandparent_node_type, { "call", "invoke" }) then
          return { kind = "method", name = word }
        end
        return { kind = "property", name = word }
      end
      local ancestor_kind = role_from_node_type(parent_node_type)
      if ancestor_kind then
        return { kind = ancestor_kind, name = word }
      end
      local fallback_kind = role_from_node_type(node_type)
      if fallback_kind then
        return { kind = fallback_kind, name = word }
      end
      return { kind = "variable", name = word }
    end

    local kind = role_from_node_type(node_type)
    if kind then
      return { kind = kind, name = word }
    end

    current = parent
    if not current then
      break
    end
  end

  return nil
end

function M.source_symbol(bufnr, cursor, word)
  local current_word = word or ""
  local semantic_symbol = semantic_token_symbol(bufnr, cursor, current_word)
  local treesitter_symbol = treesitter_source_symbol(bufnr, cursor, current_word)

  if not semantic_symbol and not treesitter_symbol then
    return nil
  end

  local kind = choose_better_kind(
    semantic_symbol and semantic_symbol.kind,
    treesitter_symbol and treesitter_symbol.kind
  )
  local name = current_word ~= "" and current_word
    or (treesitter_symbol and treesitter_symbol.name)
    or "symbol"

  return {
    kind = kind ~= "" and kind or "symbol",
    name = name ~= "" and name or "symbol",
  }
end

return M
