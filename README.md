# peeper-picker.nvim

A focused Neovim usage picker for the symbol under your cursor.

Put your cursor on a symbol and peeper-picker shows you every place it lives.
Definitions, references, and the spots other tools miss: strings, comments,
templates, prose, and generated files. The whole picture, in one list.

It works by combining two sources. Your language server provides the definitions
and references it knows about, and a fast workspace text search catches everything
it doesn't. Each result is tagged by where it came from, so you always know what
you're looking at: `REF` for code, `TXT` for strings and prose, `COM` for
comments.

## Screenshots

<p align="center">
  <img src="assets/peeper-main.png" alt="Peeper Picker main results view" width="900">
  <br>
  <sub>Main picker with results and preview</sub>
</p>

<p align="center">
  <img src="assets/peeper-filter.png" alt="Peeper Picker filter view" width="900">
  <br>
  <sub>Filter controls for scope, result type, path, and extension</sub>
</p>

## Requirements

- Neovim 0.12.2 or newer
- An attached LSP client that supports definition, declaration, or references.
  peeper-picker is LSP-gated: with no supporting client it does nothing (and
  warns). The text search only augments live LSP results; it never runs on its
  own.

## Installation

### lazy.nvim

```lua
{
  "parwest/peeper-picker.nvim",
  main = "peeper_picker",
  cmd = "PeeperPicker",
  opts = {},
  keys = {
    { "<leader>pp", "<cmd>PeeperPicker<cr>", desc = "Peeper Picker" },
  },
}
```

This lazy-loads the plugin on either `:PeeperPicker` or `<leader>pp`. Drop the
`keys` block if you only want the command and no mapping.

### Setting your own keybinding

The `keys` table above is the place to define a custom mapping. Change
`<leader>pp` to whatever you like, and keep `<cmd>PeeperPicker<cr>` as the
action. Defining it here doubles as the lazy-load trigger: the plugin only loads
the first time you press the key.

You can also map `:PeeperPicker` anywhere in your own config. The command is
registered up front without loading the picker, so a plain
`vim.keymap.set("n", "<leader>pp", "<cmd>PeeperPicker<cr>")` works too.

Or use the built-in mapping instead of defining your own. It is off by default
so the plugin never claims leader keys unless you ask:

```lua
{
  "parwest/peeper-picker.nvim",
  main = "peeper_picker",
  opts = {
    default_keymaps = {
      enabled = true,
      find = "<leader>pp",
    },
  },
}
```

The built-in mapping is created when the plugin loads, so it cannot lazy-load
the plugin by keypress on its own. If you want the keypress itself to load
peeper-picker, prefer the `keys` table above.

### Other plugin managers

Load the plugin and call setup:

```lua
require("peeper_picker").setup({
  -- options go here
})
```

Setup is optional: `:PeeperPicker` works with default options even if you never
call it. Calling setup applies your options and optional built-in keymap, and if
you later change or disable that keymap, the previous mapping is removed.

## Usage

Run `:PeeperPicker` with your cursor on a symbol. If your cursor is sitting on a
language keyword rather than a real symbol, the picker stays closed instead of
running a pointless lookup.

For Neovim help, run `:help peeper-picker`.

### Result types

Each result is tagged by where it came from:

| Tag   | Meaning                                                         |
| ----- | --------------------------------------------------------------- |
| `DEF` | A definition or declaration confirmed by the LSP                |
| `REF` | A code occurrence, either LSP-confirmed or found by text search |
| `TXT` | A textual match inside a string, template, or prose file        |
| `COM` | A textual match inside a comment                                |

`DEF` comes from the language server. `REF` includes LSP references plus
code-looking text matches that the language server did not report. `TXT` and
`COM` come from the workspace text search and only appear when the language
server didn't already report that location, so you never see the same hit twice.

Picker keys:

| Key           | Action                                                      |
| ------------- | ----------------------------------------------------------- |
| `<CR>`        | Open the selected result with your configured jump behavior |
| `<C-v>`       | Open the selected result in a new vertical split            |
| `<C-x>`       | Open the selected result in a new horizontal split          |
| `<C-t>`       | Open the selected result in a new tab                       |
| `j` / `k`     | Move selection (wraps around the ends)                      |
| `gg` / `G`    | Jump to the first / last result                             |
| `f`           | Open filters                                                |
| `=`           | If text results are capped, rescan with the expanded limit  |
| `q` / `<Esc>` | Close                                                       |

A count works like normal Vim motion: `5j` / `5k` move five rows and stop at the
end if there are fewer rows left.

Filter keys:

_you do not need to navigate your cursor to the filtering options to apply changes, just press the corresponding key_

| Key | Action                                                                            |
| --- | --------------------------------------------------------------------------------- |
| `s` | Cycle scope between file, directory, and workspace                                |
| `1` | Show code — definitions, references, and code occurrences (hides `TXT` and `COM`) |
| `2` | Show references — occurrences only, no definitions or declarations                |
| `3` | Show definitions — declarations and definitions only                              |
| `4` | Show all — everything, including string, prose, and comment matches               |
| `p` | Filter by path text. Start with `!` to exclude matching paths                     |
| `t` | Filter by extension. Start with `!` to exclude matching extensions                |
| `r` | Reset the focused filter                                                          |
| `x` | Reset all filters                                                                 |

## Configuration

Defaults:

```lua
{
  width = 92,
  height = 18,
  preview_width = 86,
  preview_context = 5,
  border = "single",
  title = " peeper-picker.nvim ",
  jump = "tabedit",
  reuse_window = true,
  expanded_match_limit = 50000,
  default_result_filtering = "all",
  default_keymaps = {
    enabled = false,
    find = "<leader>pp",
  },
  ignored_dirs = {},
  ignored_keywords = {},
}
```

The initial workspace text search is capped at 5000 matches. When it hits the
cap, the picker shows `press = to rescan: text capped at 5000 (up to 50000)`.
Press `=` to rerun the search with `expanded_match_limit`, keeping your LSP
definitions, declarations, and references in the results. The `=` action only
does something when the search was actually capped.

```lua
opts = {
  expanded_match_limit = 75000,
}
```

`default_result_filtering` sets which result filter the picker opens with. It
defaults to `"all"`, so every match is visible up front, including string,
prose, and comment hits. Set it to `"code"`, `"references"`, or `"definitions"`
to start narrower:

```lua
opts = {
  default_result_filtering = "code",
}
```

You can still cycle the filter at runtime with the `1`/`2`/`3`/`4` keys in the
filter panel; this option only controls the starting state.

`ignored_dirs` lets you add directory names to skip during the text search.
Whatever you list is **added** to the always-ignored built-in set (`.git`,
`node_modules`, `.next`, `dist`, `build`, `target`, `.cache`, `.venv`), so the
defaults keep working without any configuration:

```lua
opts = {
  ignored_dirs = { "vendor", "coverage", ".terraform" },
}
```

peeper-picker avoids opening on language keywords using Tree-sitter keyword
captures when available, plus built-in fallback keyword lists for common
development filetypes such as JavaScript, TypeScript, shell, Lua, Python, Go,
Rust, C/C++, Java, C#, PHP, Ruby, Elixir, Swift, Kotlin, Scala, SQL, Vimscript,
HTML, and CSS.

`ignored_keywords` lets you add your own cursor words that should not open the
picker. It is **added** to the built-in keyword fallbacks:

```lua
opts = {
  ignored_keywords = { "todo", "fixme" },
}
```

You can also scope additions by filetype, with `["*"]` for global additions:

```lua
opts = {
  ignored_keywords = {
    ["*"] = { "todo" },
    javascript = { "require" },
    sh = { "source" },
  },
}
```

Path and extension filters can be inverted with a leading `!`.

```text
src      show paths containing src
!src/    hide paths containing src/
js       show files ending in .js
!js      hide files ending in .js
```

Extension filtering matches filename suffixes, so `!js` hides both `core.js` and
`core.test.js`, while `!test.js` hides only `core.test.js`.

`jump` controls what `<CR>` does. It can be any Ex command that opens a file,
such as `"edit"`, `"split"`, `"vsplit"`, or `"tabedit"`.

```lua
opts = {
  jump = "edit",
}
```

It can also be a function for custom behavior:

```lua
opts = {
  jump = function(path, item)
    vim.cmd("vsplit " .. vim.fn.fnameescape(path))
  end,
}
```

By default, `reuse_window = true` jumps to an existing window if the selected
file is already open. Set it to `false` if `<CR>` should always run your `jump`
command. The split and tab picker mappings always create the requested split or
tab.

## Health

Run `:checkhealth peeper_picker` to check your Neovim version, attached LSP
clients, and whether the current buffer has an LSP client that supports
declaration, definition, or references.
