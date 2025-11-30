
# send-to-repl.nvim

A set of functions that makes copying code to a REPL easy. This can be useful when doing interactive data analysis.

For python, it automatically detects your project environment, handles IPython profiles for you, and manages terminal splits natively—no Tmux required.

It works the same for any language (that has a repl).


## Requirements

* Neovim >= 0.11
* If using with python: [uv](https://github.com/astral-sh/uv) installed on your system. You can also configure it to use python3 to start the repl outside of a virtual environment.

##  Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

This plugin does not set default keymaps, so you should define them in the `keys` table.

```lua
{
  "toreerdmann/send-to-repl.nvim",
  lazy = true,
  keys = {
    { "<leader>l", function() require("send-to-repl").send_line() end, desc = "Send line to REPL" },
    { "<leader>p", function() require("send-to-repl").send_word() end, desc = "Send word to REPL" },
    { "<leader><CR>", function() require("send-to-repl").send_paragraph() end, desc = "Send paragraph to REPL" },
    { "<leader><CR>", function() require("send-to-repl").send_visual() end, mode = "v", desc = "Send selection to REPL" },
  },
  config = function()

    -- use this to jump back and forth between the left and right panes
    vim.keymap.set("t", "<C-]>", "<C-\\><C-N><C-w>w")
    vim.keymap.set("i", "<C-]>", "<C-\\><C-N><C-w>wa")
    vim.keymap.set("n", "<C-]>", "<C-w>wa")

  end
}
```

In case the `C-l` mapping is overwritten by LazyVim's definition, you can overwrite it by adding
this to the `config/keymaps.lua` file (assuming the standard LazyVim folder structure):

```lua
local has_repl, repl = pcall(require, "send-to-repl")
if has_repl then
  vim.keymap.set("n", "<leader>l", repl.send_line, { desc = "Send line to REPL" })
  vim.keymap.set("n", "<leader>p", repl.send_word, { desc = "Send word to REPL" })
  vim.keymap.set("n", "<leader><CR>", repl.send_paragraph, { desc = "Send paragraph to REPL" })
  vim.keymap.set("v", "<leader><CR>", repl.send_visual, { desc = "Send selection to REPL" })
  vim.keymap.set("t", "<C-]>", "<C-\\><C-N><C-w>w")
  vim.keymap.set("i", "<C-]>", "<C-\\><C-N><C-w>wa")
  vim.keymap.set("n", "<C-]>", "<C-w>wa")
end
```


### Configuration

Here are some other options:

```lua
{
  "your-name/send-to-repl.nvim",
  opts = {
    repls = {
      python = {
        cmd = "python3",
        args = { "-i" }, -- -i forces interactive mode
        ensure_ipython_profile = false,
      },
      r = {
        cmd = "R",
        args = { "--no-save", "--quiet" }
      }
    }
  }
}
```


## How it works

Detection: When you send code, the plugin checks the filetype of the current file:

1. Execution:

    * If the filetype of the current file it `.py`, it runs `uv run --with ipython ipython`
    * If not, it runs `uv run --with ipython -- ipython`.

2. Profile: For python, on first run, it writes `~/.ipython/profile_nvim/ipython_config.py` to ensure:

    * %autoreload 2 is enabled.
    * Auto-indentation is disabled (for clean pasting).
    * Exit confirmation is disabled.
