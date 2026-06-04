local M = {}

local config = require("peeper_picker.config")

local function word_set(text)
  local out = {}
  for word in tostring(text or ""):gmatch("%S+") do
    out[word] = true
  end
  return out
end

local function merge(...)
  local out = {}
  for _, words in ipairs({ ... }) do
    for word in pairs(words) do
      out[word] = true
    end
  end
  return out
end

local ecma = word_set([[
  as async await break case catch class const continue debugger default delete
  do else export extends false finally for from function get if import in
  instanceof let new null of return set static super switch this throw true
  try typeof undefined var void while with yield
]])

local typescript = merge(ecma, word_set([[
  abstract any asserts bigint boolean declare enum implements infer interface is
  keyof module namespace never number object private protected public readonly
  require satisfies string symbol type unknown using
]]))

local c = word_set([[
  auto break case char const continue default do double else enum extern false
  float for goto if inline int long register restrict return short signed sizeof
  static struct switch true typedef union unsigned void volatile while
]])

local cpp = merge(c, word_set([[
  alignas alignof bool catch char16_t char32_t class concept constexpr consteval
  constinit decltype delete explicit export final friend mutable namespace new
  noexcept nullptr operator override private protected public requires template
  this thread_local throw try typename using virtual
]]))

local bash = word_set([[
  break case continue declare do done elif else esac eval exec export fi for
  function if in let local readonly return select set shift shopt source then
  time trap typeset until unset while
]])

local css = word_set("and from important in not only or to")
local html = word_set("doctype")
local sql = word_set([[
  alter and as asc begin between by case create delete desc distinct drop else
  end exists false from group having in insert into is join left like limit not
  null on or order outer right select set table then true union update values
  when where
]])
local vimscript = word_set([[
  augroup break call catch command continue def else elseif enddef endfor endif
  endtry endwhile false finally finish for function if in let lockvar return
  throw true try unlockvar while
]])

local builtin_by_filetype = {
  bash = bash,
  c = c,
  clojure = word_set([[
    catch def do else false finally fn for if let loop nil quote recur throw
    true try var
  ]]),
  cpp = cpp,
  cs = word_set([[
    abstract as base bool break byte case catch char checked class const continue
    decimal default delegate do double else enum event explicit extern false
    finally fixed float for foreach goto if implicit in int interface internal
    is lock long namespace new null object operator out override params private
    protected public readonly ref return sbyte sealed short sizeof stackalloc
    static string struct switch this throw true try typeof uint ulong unchecked
    unsafe ushort using virtual void volatile while
  ]]),
  css = css,
  dart = word_set([[
    abstract as assert async await break case catch class const continue default
    deferred do else enum export extends extension external factory false final
    finally for Function get hide if implements import in interface is late
    library mixin new null on operator part required rethrow return set show
    static super switch sync this throw true try typedef var void while with yield
  ]]),
  elixir = word_set([[
    after alias and case catch cond def defimpl defmacro defmodule defp
    defprotocol do else end false fn for if import in nil not or quote raise
    receive require rescue true try unless unquote use when
  ]]),
  erlang = word_set([[
    after and andalso band begin bnot bor bsl bsr bxor case catch cond div end
    fun if let not of or orelse receive rem try when xor
  ]]),
  go = word_set([[
    break case chan const continue default defer else fallthrough false for func
    go goto if import interface map nil package range return select struct switch
    true type var
  ]]),
  html = html,
  java = word_set([[
    abstract assert boolean break byte case catch char class const continue
    default do double else enum exports extends false final finally float for
    goto if implements import instanceof int interface long module native new
    null open opens package private protected provides public requires return
    short static strictfp super switch synchronized this throw throws to transient
    true try uses var void volatile while with yield
  ]]),
  javascript = ecma,
  julia = word_set([[
    abstract baremodule begin break catch const continue do else elseif end export
    false finally for function global if import let local macro module quote
    return struct true try using while
  ]]),
  kotlin = word_set([[
    as break catch class continue do else false finally for fun if in interface
    is null object package return super this throw true try typealias val var when
    while
  ]]),
  lua = word_set([[
    and break do else elseif end false for function goto if in local nil not or
    repeat return then true until while
  ]]),
  php = word_set([[
    abstract and array as break callable case catch class clone const continue
    declare default die do echo else elseif empty enddeclare endfor endforeach
    endif endswitch endwhile eval exit extends false final finally fn for foreach
    function global goto if implements include include_once instanceof insteadof
    interface isset list match namespace new null or print private protected
    public readonly require require_once return static switch throw trait true
    try unset use var while xor yield
  ]]),
  python = word_set([[
    False None True and as assert async await break case class continue def del
    elif else except finally for from global if import in is lambda match nonlocal
    not or pass raise return try while with yield
  ]]),
  r = word_set([[
    FALSE Inf NA NULL NaN TRUE break case else for function if in next repeat
    return switch while
  ]]),
  ruby = word_set([[
    BEGIN END alias and begin break case class def defined do else elsif end
    ensure false for if in module next nil not or redo rescue retry return self
    super then true undef unless until when while yield
  ]]),
  rust = word_set([[
    Self as async await break const continue crate dyn else enum extern false fn
    for if impl in let loop match mod move mut pub ref return self static struct
    super trait true type unsafe use where while
  ]]),
  scala = word_set([[
    abstract case catch class def do else enum export extends false final finally
    for forSome given if implicit import lazy match new null object override
    package private protected return sealed super then this throw trait true try
    type val var while with yield
  ]]),
  sql = sql,
  swift = word_set([[
    Any Self Type as associatedtype break case catch class continue default defer
    deinit do else enum extension fallthrough false fileprivate for func guard if
    import in init inout internal is let nil open operator private protocol public
    repeat return self static struct subscript super switch throw throws true try
    typealias var where while
  ]]),
  typescript = typescript,
  vim = vimscript,
}

builtin_by_filetype.javascriptreact = ecma
builtin_by_filetype.typescriptreact = typescript
builtin_by_filetype.mjs = ecma
builtin_by_filetype.cjs = ecma
builtin_by_filetype.sh = bash
builtin_by_filetype.zsh = bash
builtin_by_filetype.objc = c
builtin_by_filetype.objcpp = cpp
builtin_by_filetype.sass = css
builtin_by_filetype.scss = css
builtin_by_filetype.less = css
builtin_by_filetype.htmldjango = html
builtin_by_filetype.vimscript = vimscript
builtin_by_filetype.mysql = sql
builtin_by_filetype.plsql = sql
builtin_by_filetype.psql = sql

local case_insensitive_filetypes = {
  css = true,
  html = true,
  htmldjango = true,
  less = true,
  mysql = true,
  plsql = true,
  psql = true,
  sass = true,
  scss = true,
  sql = true,
  vim = true,
  vimscript = true,
}

local function add_words(out, words)
  if type(words) ~= "table" then
    return
  end
  for key, value in pairs(words) do
    if type(key) == "number" and type(value) == "string" and value ~= "" then
      out[value] = true
    elseif type(value) == "boolean" and value and type(key) == "string" and key ~= "" then
      out[key] = true
    end
  end
end

function M.is_ignored(word, filetype)
  if not word or word == "" then
    return false
  end

  local words = {}
  add_words(words, builtin_by_filetype[filetype])

  local configured = config.options.ignored_keywords or {}
  add_words(words, configured)
  add_words(words, configured["*"])
  add_words(words, configured[filetype])

  if words[word] then
    return true
  end
  return case_insensitive_filetypes[filetype] and words[word:lower()] == true
end

local function capture_name(entry)
  if type(entry) == "table" then
    return entry.capture or entry[1]
  end
  return nil
end

local function is_keyword_capture(name)
  return type(name) == "string" and (name == "keyword" or name:find("^keyword%.") ~= nil)
end

function M.has_keyword_capture(bufnr, row, col)
  if not vim.treesitter then
    return false
  end

  if vim.treesitter.get_captures_at_pos then
    local ok, captures = pcall(vim.treesitter.get_captures_at_pos, bufnr, row, col)
    if ok then
      for _, capture in ipairs(captures or {}) do
        if is_keyword_capture(capture_name(capture)) then
          return true
        end
      end
    end
  end

  if not vim.treesitter.get_parser or not vim.treesitter.query then
    return false
  end

  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok_parser or not parser then
    return false
  end

  local ok_lang, lang = pcall(function()
    return parser:lang()
  end)
  if not ok_lang or not lang then
    return false
  end

  local query_get = vim.treesitter.query.get or vim.treesitter.query.get_query
  if not query_get then
    return false
  end

  local ok_query, query = pcall(query_get, lang, "highlights")
  if not ok_query or not query then
    return false
  end

  local ok_parse, trees = pcall(function()
    return parser:parse()
  end)
  local tree = ok_parse and trees and trees[1] or nil
  if not tree then
    return false
  end

  local info = type(query.info) == "function" and query:info() or query.info
  local names = info and info.captures or {}
  for capture_id, node in query:iter_captures(tree:root(), bufnr, row, row + 1) do
    local sr, sc, er, ec = node:range()
    if sr <= row and row <= er and (row > sr or col >= sc) and (row < er or col < ec) then
      if is_keyword_capture(names[capture_id]) then
        return true
      end
    end
  end

  return false
end

return M
