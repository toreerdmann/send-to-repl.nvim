local M = {}

local config = {
	-- This ensures the profile is passed via args, not hardcoded strings
	ipython_args = { "--profile", "nvim" },
}

-- [[ Helper: Auto-create Profile ]] --
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
			vim.notify("Created IPython 'nvim' profile", vim.log.levels.INFO)
		end
	end
end

-- [[ Helper: Find or Create Terminal ]] --
local function get_repl_job_id()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].buftype == "terminal" then
			return vim.b[buf].terminal_job_id, false
		end
	end

	vim.cmd("vsplit | wincmd L")

	local cmd = vim.o.shell

	-- Check for UV project
	if vim.fn.executable("uv") == 1 and vim.fn.findfile("pyproject.toml", ".;") ~= "" then
		-- Prepare arguments from config
		local args = config.ipython_args
		if type(args) == "table" then
			args = table.concat(args, " ")
		end

		-- Check if IPython exists in the current venv
		if os.execute("uv run -- which ipython > /dev/null 2>&1") == 0 then
			-- It exists: Run directly
			-- Note: We use '--' to separate UV flags from IPython flags
			cmd = "uv run -- ipython " .. args
		else
			-- It does not exist: Use --with to install it ephemerally
			cmd = "uv run --with ipython -- ipython " .. args
		end
	end -- <--- This 'end' was missing in your snippet

	vim.cmd("terminal " .. cmd)

	-- [[ Auto-close logic ]] --
	local term_buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = term_buf,
		callback = function()
			-- If process exited cleanly (status 0), close the window
			if vim.v.event.status == 0 then
				-- pcall ensures we don't error if the window is already tricky to close
				vim.cmd("bdelete! " .. term_buf)
			end
		end,
	})

	local job_id = vim.b.terminal_job_id
	vim.cmd("wincmd p")
	return job_id, true
end

-- [[ Send/Toggle Functions ]] --
local function send_text(text)
	local job_id, is_new = get_repl_job_id()
	if not job_id then
		return
	end

	local clean = vim.trim(text)
	if clean == "" then
		return
	end

	local payload = clean .. "\n"

	if is_new then
		-- If we just created the terminal, wait 1000ms (1s) for IPython to boot
		-- You can adjust this number (e.g., 500, 800) if your machine is faster
		vim.defer_fn(function()
			vim.api.nvim_chan_send(job_id, payload)
		end, 500)
	else
		-- Otherwise send immediately
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
	ensure_ipython_profile()
	config = vim.tbl_deep_extend("force", config, opts or {})
end

return M
