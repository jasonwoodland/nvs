# nvs

List and attach to running Neovim sessions.

Discovers Neovim instances by scanning Unix and TCP sockets via `lsof`, showing each session's working directory, current buffer, and attach status.

## CLI

```
nvs              # fzf picker (falls back to list if fzf is unavailable)
nvs <index>      # attach to session by index
nvs --help
```

Zsh completions: `eval "$(nvs --zsh-completion)"`

## Telescope picker

A Lua module provides a [Telescope](https://github.com/nvim-telescope/telescope.nvim) picker with live buffer preview of each session.

```lua
require("nvs").setup()                       -- binds <Leader>s
require("nvs").setup({ key = "<Space>ns" })  -- custom key
require("nvs").setup({ key = false })        -- no keymap, call require("nvs").pick({}) yourself
```

## Requirements

- Neovim with `--remote-ui` support
- `lsof`
- `fzf` (optional, for the CLI picker)
- `telescope.nvim` (optional, for the Neovim picker)

## Installation

Add the repo directory to your `PATH`:

```sh
# ~/.zshrc
PATH="$HOME/path/to/nvs:$PATH"
```

### Telescope Picker

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jasonwoodland/nvs",
  opts = {},
}
```
