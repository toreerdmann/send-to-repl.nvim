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
			return vim.b[buf].terminal_job_id, false, buf
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
	return job_id, true, term_buf
end

-- [[ Helper: Wait for REPL Prompt ]] --
local function wait_for_repl(buf, job_id, callback)
	local timer = vim.loop.new_timer()
	local attempts = 0
	-- Increase max attempts to 200 (200 * 50ms = 10 seconds) for CI robustness
	local max_attempts = 200

	timer:start(
		0,
		50,
		vim.schedule_wrap(function()
			attempts = attempts + 1

			local chan_info = vim.api.nvim_get_chan_info(job_id)
			local is_closed = next(chan_info) == nil

			-- Fail if closed or buffer invalid
			if not vim.api.nvim_buf_is_valid(buf) or is_closed then
				timer:stop()
				timer:close()
				return -- Do not call callback if the channel died
			end

			-- Check for prompt
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local found_prompt = false
			for _, line in ipairs(lines) do
				if line:match(">>>") or line:match("[>%%$#%]:?]%s*$") then
					found_prompt = true
					break
				end
			end

			if found_prompt then
				timer:stop()
				timer:close()
				callback()
			elseif attempts > max_attempts then
				timer:stop()
				timer:close()
				-- Optional: print a warning here so you know it timed out
				print("Warning: REPL wait timed out, sending anyway...")
				callback()
			end
		end)
	)
end

-- [[ Send/Toggle Functions ]] --
local function send_text(text)
	local job_id, is_new, term_buf = get_repl_job_id()
	if not job_id then
		return
	end

	local ft = vim.bo.filetype
	local is_configured = config.repls[ft] ~= nil

	if is_new and not is_configured then
		return
	end

	-- 1. Remove ONLY trailing whitespace/newlines
	local clean = text:gsub("%s+$", "")
	if clean == "" then
		return
	end

	-- 2. Smart Enter Logic
	local lines = vim.split(clean, "\n")
	local last_line = lines[#lines] or ""

	local ending = "\n"
	if last_line:match("^%s+") then
		ending = "\n\n"
	end

	-- 3. Bracketed Paste Construction
	local payload = "\27[200~" .. clean .. "\27[201~" .. ending

	-- Helper to safely send
	local function safe_send()
		-- pcall protects us if the job/channel died
		local ok, err = pcall(vim.api.nvim_chan_send, job_id, payload)
		if not ok then
			print("Error: Failed to send to REPL (Job " .. job_id .. "): " .. tostring(err))
		end
	end

	if is_new then
		wait_for_repl(term_buf, job_id, function()
			safe_send()
		end)
	else
		safe_send()
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
