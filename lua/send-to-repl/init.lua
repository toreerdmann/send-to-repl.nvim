local M = {}

-- [[ Configuration ]] --
local config = {
	repls = {
		-- Python: Default to the robust 'uv' workflow
		python = {
			cmd = "uv",
			args = { "run", "--with", "ipython", "--", "ipython", "--profile", "nvim" },
			ensure_ipython_profile = true,
		},
		-- Other Defaults
		lua = { cmd = "lua", args = {} },
		sh = { cmd = "bash", args = {} },
		r = { cmd = "R", args = {} },
		julia = { cmd = "julia", args = {} },
		javascript = { cmd = "node", args = {} },
		typescript = { cmd = "ts-node", args = {} },
	},
}

-- [[ Helper: Auto-create Python Profile ]] --
local function ensure_ipython_profile()
	local home = os.getenv("HOME")
	local profile_dir = home .. "/.ipython/profile_nvim"
	local config_file = profile_dir .. "/ipython_config.py"

	if vim.fn.isdirectory(profile_dir) == 0 then
		vim.fn.mkdir(profile_dir, "p")
	end

	if vim.fn.filereadable(config_file) == 0 then
		local content = [[
c = get_config()
c.TerminalIPythonApp.display_banner = False
c.InteractiveShellApp.exec_lines = ['%load_ext autoreload', '%autoreload 2']
c.InteractiveShell.autoindent = False
c.TerminalInteractiveShell.confirm_exit = False
]]
		local f = io.open(config_file, "w")
		if f then
			f:write(content)
			f:close()
		end
	end
end

-- [[ Helper: Construct Command ]] --
local function get_repl_command()
	local ft = vim.bo.filetype
	local def = config.repls[ft]

	-- 1. If no config for this filetype, fallback to default shell
	if not def then
		return vim.o.shell
	end

	-- 2. Handle Side Effects
	if def.ensure_ipython_profile then
		ensure_ipython_profile()
	end

	-- 3. Construct command
	local cmd_str = def.cmd
	if def.args and #def.args > 0 then
		cmd_str = cmd_str .. " " .. table.concat(def.args, " ")
	end

	return cmd_str
end

-- [[ Helper: Find or Create Terminal ]] --
local function get_repl_job_id()
	-- Search for existing terminal
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].buftype == "terminal" then
			return vim.b[buf].terminal_job_id, false -- existing
		end
	end

	-- Create split and start terminal
	vim.cmd("vsplit | wincmd L")
	local cmd = get_repl_command()
	vim.cmd("terminal " .. cmd)

	-- Auto-close logic
	local term_buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = term_buf,
		callback = function()
			if vim.v.event.status == 0 then
				vim.cmd("bdelete! " .. term_buf)
			end
		end,
	})

	local job_id = vim.b.terminal_job_id
	vim.cmd("wincmd p")
	return job_id, true -- new
end

-- [[ Send/Toggle Functions ]] --
local function send_text(text)
	local job_id, is_new = get_repl_job_id()
	if not job_id then
		return
	end

	local ft = vim.bo.filetype
	local is_configured = config.repls[ft] ~= nil

	if is_new and not is_configured then
		return
	end

	-- 1. Remove ONLY trailing whitespace/newlines (keep leading indent!)
	local clean = text:gsub("%s+$", "")
	if clean == "" then
		return
	end

	-- 2. Smart Enter Logic
	-- Split by newline to check the last line
	local lines = vim.split(clean, "\n")
	local last_line = lines[#lines] or ""

	-- If the last line is indented (starts with space/tab), we need two Enters.
	-- Otherwise (closed block), we only need one.
	local ending = "\n"
	if last_line:match("^%s+") then
		ending = "\n\n"
	end

	-- 3. Bracketed Paste Construction
	-- \27[200~ ... \27[201~ protects the indentation and empty lines inside
	local payload = "\27[200~" .. clean .. "\27[201~" .. ending

	if is_new then
		vim.defer_fn(function()
			vim.api.nvim_chan_send(job_id, payload)
		end, 500)
	else
		vim.api.nvim_chan_send(job_id, payload)
	end
end

function M.send_line()
	send_text(vim.api.nvim_get_current_line())
end
function M.send_word()
	vim.cmd('silent! noau normal! "vyiw')
	send_text(vim.fn.getreg("v"))
end
function M.send_paragraph()
	local view = vim.fn.winsaveview()
	vim.cmd('silent! noau normal! vip"vy')
	send_text(vim.fn.getreg("v"))
	vim.fn.winrestview(view)
end
function M.send_visual()
	vim.cmd('silent! noau normal! "vy')
	send_text(vim.fn.getreg("v"))
end

function M.toggle_repl()
	local repl_win = nil
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].buftype == "terminal" then
			repl_win = win
			break
		end
	end
	if repl_win then
		if vim.api.nvim_get_current_win() == repl_win then
			vim.cmd("wincmd p")
		else
			vim.api.nvim_set_current_win(repl_win)
			vim.cmd("startinsert")
		end
	else
		get_repl_job_id()
		vim.cmd("wincmd p")
		vim.cmd("startinsert")
	end
end

-- [[ Setup ]] --
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

return M
