# peeper-picker.nvim

A small Neovim picker for jumping through LSP definitions, declarations, and
references for the symbol under your cursor.

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
- An attached LSP client that supports definition, declaration, or references

## Installation

Recommended with lazy.nvim:

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

This keeps the mapping in your personal Neovim config, where it belongs, and
lets lazy.nvim load the plugin from either `:PeeperPicker` or `<leader>pp`.

If you only want the command and no keymap:

```lua
{
  "parwest/peeper-picker.nvim",
  main = "peeper_picker",
  cmd = "PeeperPicker",
  opts = {},
}
```

Or enable the built-in default mapping. It is off by default so the plugin does
not take over your leader keyspace unless you ask it to. With lazy.nvim, prefer
the `keys` example above if you want the key itself to lazy-load the plugin.

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

With another plugin manager, load the plugin and call setup:

```lua
require("peeper_picker").setup({
  -- options go here
})
```

The plugin defines `:PeeperPicker` from `plugin/peeper-picker.lua` without
loading the full picker. Calling `require("peeper_picker").setup({ ... })`
applies your options and optional built-in keymap. If you enable the built-in
default keymap and later change or disable it with another setup call, the
previous built-in mapping is removed.

If you do not call `setup()`, `:PeeperPicker` still works with the default
options.

## Usage

Run `:PeeperPicker` with your cursor on a symbol.

For Neovim help, run `:help peeper-picker`.

Picker keys:

| Key | Action |
| --- | --- |
| `<CR>` | Open the selected result with your configured jump behavior |
| `<C-v>` | Open the selected result in a new vertical split |
| `<C-x>` | Open the selected result in a new horizontal split |
| `<C-t>` | Open the selected result in a new tab |
| `j` / `k` | Move selection |
| `f` | Open filters |
| `q` / `<Esc>` | Close |

Filter keys:

| Key | Action |
| --- | --- |
| `s` | Cycle scope between file, directory, and workspace |
| `1` | Show references only |
| `2` | Show definitions/declarations only |
| `3` | Show both |
| `p` | Filter by path text |
| `t` | Filter by extension |
| `r` | Reset the focused filter |
| `x` | Reset all filters |

## Configuration

Defaults:

```lua
{
  width = 92,
  height = 18,
  preview_width = 86,
  preview_height = 14,
  preview_context = 5,
  border = "single",
  title = " peeper-picker.nvim ",
  jump = "tabedit",
  reuse_window = true,
  default_keymaps = {
    enabled = false,
    find = "<leader>pp",
  },
}
```

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
