-- Isolated Neovim test-drive configuration for send-to-repl.nvim
local plugin_dir = vim.fn.getcwd()
vim.opt.rtp:append(plugin_dir)

-- Setup leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Basic UI / Editor settings
vim.o.termguicolors = true
vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
vim.o.signcolumn = "yes"
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.swapfile = false
vim.o.showcmd = true
vim.o.cmdheight = 1

-- Require and configure send-to-repl
local repl = require("send-to-repl")
repl.setup({
	layout = {
		split = "vertical",
		size = 0.45,
	},
})

-- Visual Feedback Helper
local function notify_key(key, desc)
	vim.api.nvim_echo({ { string.format(" Key: %s  ->  %s", key, desc), "Question" } }, false, {})
end

-- Keymaps with visual feedback for demo recording
local map = vim.keymap.set
map("n", "<leader>l", function()
	notify_key("<Space>l", "Send Line to REPL")
	repl.send_line()
end, { desc = "Send line" })

map("n", "<leader>p", function()
	notify_key("<Space>p", "Send Word to REPL")
	repl.send_word()
end, { desc = "Send word" })

map("n", "<leader>c", function()
	notify_key("<Space>c", "Send Cell to REPL (# %%)")
	repl.send_cell()
end, { desc = "Send code cell (# %%)" })

map("n", "<leader><CR>", function()
	notify_key("<Space><CR>", "Send Paragraph to REPL")
	repl.send_paragraph()
end, { desc = "Send paragraph" })

map("v", "<leader><CR>", function()
	notify_key("<Space><CR>", "Send Visual Selection to REPL")
	repl.send_visual()
end, { desc = "Send visual selection" })

map("n", "<leader>rf", function()
	notify_key("<Space>rf", "Send Whole File to REPL")
	repl.send_file()
end, { desc = "Send whole file" })

map("n", "<leader>rt", function()
	notify_key("<Space>rt", "Toggle REPL Window Focus")
	repl.toggle_repl()
end, { desc = "Toggle REPL window" })

map("n", "<leader>rr", function()
	notify_key("<Space>rr", "Restart REPL")
	repl.restart_repl()
end, { desc = "Restart REPL" })

map("n", "<leader>rc", function()
	notify_key("<Space>rc", "Clear REPL Screen")
	repl.clear()
end, { desc = "Clear REPL" })

map("n", "<leader>ri", function()
	notify_key("<Space>ri", "Interrupt REPL (Ctrl-C)")
	repl.interrupt()
end, { desc = "Interrupt REPL (Ctrl-C)" })

map("n", "gxc", repl.send_operator, { desc = "Send motion (operator)" })

-- Convenient navigation between windows
map("t", "<C-w>h", "<C-\\><C-N><C-w>h")
map("t", "<C-w>l", "<C-\\><C-N><C-w>l")
map("t", "<C-]>", "<C-\\><C-N><C-w>p")
map("n", "<C-]>", "<C-w>p")

-- Create demo buffer if no file was specified
if vim.fn.argc() == 0 then
	local demo_lines = {
		"# ========================================================",
		"# send-to-repl.nvim Interactive Test Drive",
		"# ========================================================",
		"# Keymaps configured (Leader is <Space>):",
		"#   <Space>l    -> Send current line",
		"#   <Space>c    -> Send current cell (# %%)",
		"#   <Space><CR> -> Send paragraph (or selection in visual mode)",
		"#   <Space>p    -> Send word under cursor",
		"#   <Space>rf   -> Send entire buffer",
		"#   <Space>rt   -> Toggle REPL focus",
		"#   <Space>rr   -> Restart REPL",
		"#   gxc{motion} -> Send motion (e.g. gxcip, gxc2j)",
		"#   <C-]>       -> Jump between code and REPL window",
		"# ========================================================",
		"",
		"# %% Cell 1: Basic variables",
		"name = 'Neovim User'",
		"count = 42",
		"print(f'Hello {name}! Count is: {count}')",
		"",
		"# %% Cell 2: Function definition & call",
		"def square_and_add(n, bonus=10):",
		"    return (n ** 2) + bonus",
		"",
		"result = square_and_add(5)",
		"print(f'Result: {result}')",
		"",
		"# %% Cell 3: Loop test",
		"for i in range(3):",
		"    print(f'Step {i + 1} complete')",
	}

	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, demo_lines)
	vim.bo[buf].filetype = "python"
	vim.bo[buf].buftype = ""
	vim.bo[buf].modified = false
end
