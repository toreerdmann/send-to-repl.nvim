local plugin_dir = vim.fn.getcwd()
local plenary_dir = plugin_dir .. "/vendor/plenary.nvim"

-- 1. Check vendor directory first, then /tmp
if vim.fn.isdirectory(plenary_dir) == 0 then
	plenary_dir = "/tmp/plenary.nvim"
	if vim.fn.isdirectory(plenary_dir) == 0 then
		vim.fn.system({ "git", "clone", "--depth", "1", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
	end
end

-- 2. Add paths to Neovim runtime
vim.opt.rtp:append(plenary_dir)
vim.opt.rtp:append(plugin_dir)

-- 3. Basic settings for testing
vim.cmd("runtime! plugin/plenary.vim")
vim.o.termguicolors = true
vim.o.swapfile = false
