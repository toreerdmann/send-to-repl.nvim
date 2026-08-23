---@class ReplDef
---@field cmd string|fun():string Command to run (e.g. "uv", "python3", "ipython", "R")
---@field args? (string|fun():string)[]|fun():string[] Command line arguments
---@field ensure_ipython_profile? boolean Whether to automatically configure ~/.ipython/profile_nvim
---@field prompt_pattern? string Custom regex pattern to match prompt on boot

---@class LayoutConfig
---@field split? "vertical"|"horizontal"|"tab" Direction of split (default: "vertical")
---@field size? number Split size (columns/rows if >= 1, fraction of window if < 1, e.g. 0.4)
---@field open? fun(cmd: string): number Custom function to open terminal window returning buffer number

---@class SendToReplConfig
---@field layout? LayoutConfig
---@field cell_marker? string|table<string, string> Pattern to match cell delimiter (default: filetype specific or "^%s*#%s*%%%%")
---@field bracketed_paste? boolean Whether to use bracketed paste escape sequences (default: true)
---@field wait_for_prompt? boolean Whether to wait for prompt on initial launch (default: true)
---@field repls? table<string, ReplDef>

local M = {}

local uv = vim.uv or vim.loop

-- [[ Default Configuration ]] --
local config = {
	layout = {
		split = "vertical", -- "vertical" | "horizontal" | "tab"
		size = nil, -- nil for default split, or number (e.g. 0.4 for 40% or 80 for columns)
	},
	cell_marker = nil, -- string or table<filetype, pattern>
	bracketed_paste = true,
	wait_for_prompt = true,
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
		bash = { cmd = "bash", args = {} },
		zsh = { cmd = "zsh", args = {} },
		r = { cmd = "R", args = {} },
		julia = { cmd = "julia", args = {} },
		javascript = { cmd = "node", args = {} },
		typescript = { cmd = "ts-node", args = {} },
	},
}

local default_cell_markers = {
	python = "^%s*#%s*%%%%",
	r = "^%s*#%s*%%%%",
	julia = "^%s*#%s*%%%%",
	sh = "^%s*#%s*%%%%",
	bash = "^%s*#%s*%%%%",
	zsh = "^%s*#%s*%%%%",
	lua = "^%s*%-%-%s*%%%%",
	sql = "^%s*%-%-%s*%%%%",
	javascript = "^%s*//%s*%%%%",
	typescript = "^%s*//%s*%%%%",
	cpp = "^%s*//%s*%%%%",
	c = "^%s*//%s*%%%%",
	rust = "^%s*//%s*%%%%",
	scala = "^%s*//%s*%%%%",
}

-- [[ Helper: Auto-create Python Profile ]] --
local function ensure_ipython_profile()
	local home = vim.fs.normalize("~")
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
	local def = config.repls and config.repls[ft]

	-- 1. If no config for this filetype, fallback to default shell
	if not def then
		return vim.o.shell
	end

	-- 2. Handle Side Effects
	if def.ensure_ipython_profile then
		ensure_ipython_profile()
	end

	-- 3. Construct command
	local cmd = def.cmd
	if type(cmd) == "function" then
		cmd = cmd()
	end

	local args = def.args or {}
	if type(args) == "function" then
		args = args()
	end

	local cmd_parts = { tostring(cmd) }
	if type(args) == "table" then
		for _, arg in ipairs(args) do
			if type(arg) == "function" then
				table.insert(cmd_parts, tostring(arg()))
			else
				table.insert(cmd_parts, tostring(arg))
			end
		end
	elseif type(args) == "string" and args ~= "" then
		table.insert(cmd_parts, args)
	end

	return table.concat(cmd_parts, " ")
end

-- [[ Helper: Find existing REPL buffer ]] --
local function find_existing_repl()
	-- 1. Search in current tabpage windows
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.b[buf].send_to_repl and vim.api.nvim_buf_is_valid(buf) then
			return buf, win
		end
	end

	-- 2. Search all buffers
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.b[buf].send_to_repl and vim.api.nvim_buf_is_valid(buf) then
			local wins = vim.fn.win_findbuf(buf)
			return buf, wins[1]
		end
	end

	return nil, nil
end

-- [[ Helper: Open REPL Window ]] --
local function open_repl_window(cmd)
	local layout = config.layout or {}
	if type(layout.open) == "function" then
		return layout.open(cmd)
	end

	local split = layout.split or "vertical"
	local size = layout.size

	if split == "vertical" then
		vim.cmd("vsplit | wincmd L")
		if size and size > 0 then
			if size < 1 then
				local cols = vim.o.columns
				vim.cmd("vertical resize " .. math.floor(cols * size))
			else
				vim.cmd("vertical resize " .. math.floor(size))
			end
		end
	elseif split == "horizontal" then
		vim.cmd("split | wincmd J")
		if size and size > 0 then
			if size < 1 then
				local lines = vim.o.lines
				vim.cmd("resize " .. math.floor(lines * size))
			else
				vim.cmd("resize " .. math.floor(size))
			end
		end
	elseif split == "tab" then
		vim.cmd("tabnew")
	else
		vim.cmd("vsplit | wincmd L")
	end

	vim.cmd("terminal " .. cmd)
	local term_buf = vim.api.nvim_get_current_buf()
	vim.b[term_buf].send_to_repl = true
	vim.b[term_buf].send_to_repl_ft = vim.bo.filetype

	return term_buf
end

-- [[ Helper: Find or Create Terminal ]] --
local function get_repl_job_id()
	local term_buf, _ = find_existing_repl()

	if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
		local job_id = vim.b[term_buf].terminal_job_id
		if job_id then
			local chan_info = vim.api.nvim_get_chan_info(job_id)
			if next(chan_info) ~= nil then
				return job_id, false, term_buf
			end
		end
	end

	-- Create split and start terminal
	local cur_win = vim.api.nvim_get_current_win()
	local cmd = get_repl_command()
	local new_term_buf = open_repl_window(cmd)

	-- Auto-close logic on TermClose if clean exit
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = new_term_buf,
		callback = function()
			if vim.v.event.status == 0 then
				pcall(vim.api.nvim_buf_delete, new_term_buf, { force = true })
			end
		end,
	})

	local job_id = vim.b[new_term_buf].terminal_job_id

	if cur_win and vim.api.nvim_win_is_valid(cur_win) then
		vim.api.nvim_set_current_win(cur_win)
	end

	return job_id, true, new_term_buf
end

-- [[ Helper: Wait for REPL Prompt ]] --
local function wait_for_repl(buf, job_id, callback)
	if not config.wait_for_prompt then
		callback()
		return
	end

	local ft = vim.bo.filetype
	local def = config.repls and config.repls[ft]
	local custom_pattern = def and def.prompt_pattern

	local timer = uv.new_timer()
	local attempts = 0
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
				if not timer:is_closing() then
					timer:close()
				end
				return
			end

			-- Check for prompt
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local found_prompt = false
			for _, line in ipairs(lines) do
				if custom_pattern and line:match(custom_pattern) then
					found_prompt = true
					break
				elseif line:match(">>>") or line:match("[>%%$#%]:?]%s*$") then
					found_prompt = true
					break
				end
			end

			if found_prompt then
				timer:stop()
				if not timer:is_closing() then
					timer:close()
				end
				callback()
			elseif attempts > max_attempts then
				timer:stop()
				if not timer:is_closing() then
					timer:close()
				end
				callback()
			end
		end)
	)
end

local is_booting = false
local pending_queue = {}

local function flush_queue(job_id)
	is_booting = false
	while #pending_queue > 0 do
		local payload = table.remove(pending_queue, 1)
		local ok, err = pcall(vim.api.nvim_chan_send, job_id, payload)
		if not ok then
			vim.notify("Error sending to REPL (Job " .. tostring(job_id) .. "): " .. tostring(err), vim.log.levels.ERROR)
		end
	end
end

-- [[ Send Core Function ]] --
local function send_text(text)
	if not text or text == "" then
		return
	end

	local job_id, is_new, term_buf = get_repl_job_id()
	if not job_id then
		return
	end

	local ft = vim.bo.filetype
	local is_configured = config.repls and config.repls[ft] ~= nil

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

	-- 3. Payload Construction
	local payload
	if config.bracketed_paste then
		payload = "\27[200~" .. clean .. "\27[201~" .. ending
	else
		payload = clean .. ending
	end

	if is_new or is_booting then
		table.insert(pending_queue, payload)
		if is_new then
			is_booting = true
			wait_for_repl(term_buf, job_id, function()
				flush_queue(job_id)
			end)
		end
	else
		local ok, err = pcall(vim.api.nvim_chan_send, job_id, payload)
		if not ok then
			vim.notify("Error sending to REPL (Job " .. tostring(job_id) .. "): " .. tostring(err), vim.log.levels.ERROR)
		end
	end
end

-- [[ Cell Helper ]] --
local function get_cell_marker(ft)
	if type(config.cell_marker) == "string" then
		return config.cell_marker
	elseif type(config.cell_marker) == "table" and config.cell_marker[ft] then
		return config.cell_marker[ft]
	end
	return default_cell_markers[ft] or "^%s*#%s*%%%%"
end

-- [[ Public API: Send Functions ]] --

--- Send arbitrary string to the REPL
---@param text string
function M.send(text)
	send_text(text)
end

--- Send raw characters to the REPL channel without formatting or bracketed paste
---@param text string
function M.send_raw(text)
	local job_id = get_repl_job_id()
	if job_id and text then
		pcall(vim.api.nvim_chan_send, job_id, text)
	end
end

--- Send the current line under cursor
function M.send_line()
	send_text(vim.api.nvim_get_current_line())
end

--- Send the word under cursor without modifying registers
function M.send_word()
	local word = vim.fn.expand("<cword>")
	if word and word ~= "" then
		send_text(word)
	end
end

--- Send the current paragraph without modifying registers
function M.send_paragraph()
	local total = vim.api.nvim_buf_line_count(0)
	if total == 0 then
		return
	end

	local cur_row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, total, false)

	if lines[cur_row] and lines[cur_row]:match("^%s*$") then
		return
	end

	local start_row = cur_row
	while start_row > 1 and not lines[start_row - 1]:match("^%s*$") do
		start_row = start_row - 1
	end

	local end_row = cur_row
	while end_row < total and not lines[end_row + 1]:match("^%s*$") do
		end_row = end_row + 1
	end

	local p_lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
	send_text(table.concat(p_lines, "\n"))
end

--- Send visual selection without modifying registers
function M.send_visual()
	local mode = vim.fn.mode()
	if mode:match("[vV\22]") then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
	end

	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local visual_type = vim.fn.visualmode()

	local region = vim.fn.getregion(start_pos, end_pos, { type = visual_type })
	if region and #region > 0 then
		send_text(table.concat(region, "\n"))
	end
end

--- Send code cell delimited by marker (e.g. # %%, ##)
function M.send_cell()
	local ft = vim.bo.filetype
	local marker = get_cell_marker(ft)
	local total = vim.api.nvim_buf_line_count(0)
	if total == 0 then
		return
	end

	local cur_row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, total, false)

	local start_line = 1
	for i = cur_row, 1, -1 do
		if lines[i]:match(marker) then
			start_line = i + 1
			break
		end
	end

	local end_line = total
	local scan_start = math.max(start_line, cur_row + 1)
	for i = scan_start, total do
		if lines[i]:match(marker) then
			end_line = i - 1
			break
		end
	end

	if start_line <= end_line then
		local cell_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
		send_text(table.concat(cell_lines, "\n"))
	end
end

--- Send a line range (1-indexed, inclusive)
---@param line1 integer
---@param line2 integer
function M.send_range(line1, line2)
	local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
	send_text(table.concat(lines, "\n"))
end

--- Send entire file / buffer
function M.send_file()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	send_text(table.concat(lines, "\n"))
end
M.send_buffer = M.send_file

--- Operatorfunc for motions (e.g. gxcip, gxc2j)
---@param type? string
function M.send_operator(type)
	if type == nil then
		vim.go.operatorfunc = "v:lua.require'send-to-repl'.send_operator"
		return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("g@", true, false, true), "m", false)
	end

	local mark_start = vim.fn.getpos("'[")
	local mark_end = vim.fn.getpos("']")
	local region = vim.fn.getregion(mark_start, mark_end, { type = type })
	if region and #region > 0 then
		send_text(table.concat(region, "\n"))
	end
end

-- [[ REPL Control Functions ]] --

--- Toggle focus or visibility of the REPL window
function M.toggle_repl()
	local term_buf, win = find_existing_repl()
	if term_buf and win and vim.api.nvim_win_is_valid(win) then
		if vim.api.nvim_get_current_win() == win then
			vim.cmd("wincmd p")
		else
			vim.api.nvim_set_current_win(win)
			vim.cmd("startinsert")
		end
	elseif term_buf and vim.api.nvim_buf_is_valid(term_buf) then
		local layout = config.layout or {}
		local split = layout.split or "vertical"
		if split == "vertical" then
			vim.cmd("vsplit | wincmd L")
		elseif split == "horizontal" then
			vim.cmd("split | wincmd J")
		elseif split == "tab" then
			vim.cmd("tabnew")
		else
			vim.cmd("vsplit | wincmd L")
		end
		vim.api.nvim_set_current_buf(term_buf)
		vim.cmd("startinsert")
	else
		get_repl_job_id()
		local _, new_win = find_existing_repl()
		if new_win and vim.api.nvim_win_is_valid(new_win) then
			vim.api.nvim_set_current_win(new_win)
			vim.cmd("startinsert")
		end
	end
end

--- Restart the REPL process
function M.restart_repl()
	local term_buf, _ = find_existing_repl()
	if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
		local job_id = vim.b[term_buf].terminal_job_id
		if job_id then
			pcall(vim.fn.jobstop, job_id)
		end
		pcall(vim.api.nvim_buf_delete, term_buf, { force = true })
	end
	get_repl_job_id()
end

--- Send interrupt signal (Ctrl-C) to the REPL
function M.interrupt()
	local job_id = get_repl_job_id()
	if job_id then
		pcall(vim.api.nvim_chan_send, job_id, "\3")
	end
end

--- Send clear screen signal (Ctrl-L) to the REPL
function M.clear()
	local job_id = get_repl_job_id()
	if job_id then
		pcall(vim.api.nvim_chan_send, job_id, "\12")
	end
end
M.clear_repl = M.clear

-- [[ User Commands Registration ]] --
local function register_commands()
	local cmd = vim.api.nvim_create_user_command

	cmd("SendToReplLine", function() M.send_line() end, { desc = "Send current line to REPL" })
	cmd("SendToReplWord", function() M.send_word() end, { desc = "Send word under cursor to REPL" })
	cmd("SendToReplParagraph", function() M.send_paragraph() end, { desc = "Send paragraph to REPL" })
	cmd("SendToReplVisual", function() M.send_visual() end, { range = true, desc = "Send visual selection to REPL" })
	cmd("SendToReplCell", function() M.send_cell() end, { desc = "Send current code cell to REPL" })
	cmd("SendToReplBuffer", function() M.send_buffer() end, { desc = "Send entire buffer to REPL" })
	cmd("SendToReplFile", function() M.send_file() end, { desc = "Send entire file to REPL" })
	cmd("SendToReplToggle", function() M.toggle_repl() end, { desc = "Toggle/Focus REPL window" })
	cmd("SendToReplRestart", function() M.restart_repl() end, { desc = "Restart REPL" })
	cmd("SendToReplClear", function() M.clear() end, { desc = "Clear REPL screen" })
	cmd("SendToReplInterrupt", function() M.interrupt() end, { desc = "Send SIGINT (Ctrl-C) to REPL" })
	cmd("SendToReplSend", function(opts)
		M.send(opts.args)
	end, { nargs = "+", desc = "Send custom text to REPL" })
end

register_commands()

-- [[ Setup ]] --
---@param opts? SendToReplConfig
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

return M

