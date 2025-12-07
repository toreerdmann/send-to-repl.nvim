local plenary_dir = "/tmp/plenary.nvim"
local plugin_dir = vim.fn.getcwd()

-- 1. Auto-download plenary if missing
if vim.fn.isdirectory(plenary_dir) == 0 then
	print("Cloning plenary.nvim to /tmp...")
	vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
end

-- 2. Add paths to Neovim runtime
vim.opt.rtp:append(plenary_dir)
vim.opt.rtp:append(plugin_dir)

-- 3. Basic settings for testing
vim.cmd("runtime! plugin/plenary.vim")
vim.o.termguicolors = true
vim.o.swapfile = false
