---@class ReplDef
---@field cmd string|fun():string Command to run (e.g. "uv", "python3", "ipython", "R")
---@field args? (string|fun():string)[]|fun():string[] Command line arguments
---@field ensure_ipython_profile? boolean Whether to automatically configure ~/.ipython/profile_nvim
---@field prompt_pattern? string Custom regex pattern to match prompt on boot
---@field no_venv_packages? string[]|string|fun():string[] Packages to include when no venv is detected
---@field default_packages? string[]|string|fun():string[] Alias for no_venv_packages
---@field no_venv_cmd? string|fun():string Custom command when no venv is detected
---@field no_venv_args? (string|fun():string)[]|fun():string[] Custom args when no venv is detected
---@field detect_venv? boolean Whether to automatically detect virtual environments (default: true)

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

-- Session state
M._last_custom_opts = nil

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
			no_venv_packages = {},
			detect_venv = true,
		},
		-- Other Defaults
		lua = { cmd = "lua", args = {} },
		sh = { cmd = "bash", args = {} },
		bash = { cmd = "bash", args = {} },
		zsh = { cmd = "zsh", args = {} },
		r = { cmd = "R", args = { "--no-save", "--quiet" } },
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

-- [[ Helper: Detect Python Virtual Environment ]] --
--- Check if a virtual environment or Python project is detected
---@param dir? string Optional path to search from (defaults to current buffer or cwd)
---@return boolean detected Whether a venv or project was found
---@return string|nil path Path to the venv or project marker found
function M.has_venv(dir)
	-- 1. Check environment variable
	local env_venv = vim.env.VIRTUAL_ENV or vim.env.CONDA_PREFIX
	if env_venv and env_venv ~= "" and vim.fn.isdirectory(env_venv) == 1 then
		return true, env_venv
	end

	-- 2. Determine search path (buffer directory or current working directory)
	local search_path = dir
	if not search_path or search_path == "" then
		local buf_name = vim.api.nvim_buf_get_name(0)
		if buf_name ~= "" then
			search_path = vim.fs.dirname(buf_name)
		else
			search_path = uv.cwd() or vim.fn.getcwd()
		end
	end

	search_path = vim.fs.normalize(search_path)
	local home_dir = vim.fs.normalize("~")

	-- Determine boundary (stop_dir) for upward search:
	-- If inside a git repository, bound search to the git repository root.
	-- Otherwise, stop before searching the home directory root.
	local stop_dir
	local git_roots = vim.fs.find(".git", { upward = true, path = search_path })
	if git_roots and #git_roots > 0 then
		local git_project_root = vim.fs.dirname(git_roots[1])
		stop_dir = vim.fs.dirname(git_project_root)
	elseif search_path ~= home_dir then
		stop_dir = home_dir
	end

	-- 3. Search upward for virtual environment directories
	local venv_patterns = { ".venv", "venv", ".conda" }
	local found_dirs = vim.fs.find(venv_patterns, { upward = true, path = search_path, stop = stop_dir, type = "directory" })
	if found_dirs and #found_dirs > 0 then
		return true, found_dirs[1]
	end

	-- 4. Search upward for project definition files that uv/python treats as environments
	local project_patterns = { "pyproject.toml", "uv.lock", "poetry.lock", "Pipfile" }
	local found_files = vim.fs.find(project_patterns, { upward = true, path = search_path, stop = stop_dir, type = "file" })
	if found_files and #found_files > 0 then
		return true, found_files[1]
	end

	return false, nil
end

-- [[ Helper: Parse Package List ]] --
local function parse_packages(pkgs)
	if not pkgs then
		return {}
	end
	if type(pkgs) == "function" then
		pkgs = pkgs()
	end
	local list = {}
	if type(pkgs) == "string" then
		for p in pkgs:gmatch("[^,%s]+") do
			table.insert(list, p)
		end
	elseif type(pkgs) == "table" then
		for _, item in ipairs(pkgs) do
			if type(item) == "string" then
				for p in item:gmatch("[^,%s]+") do
					table.insert(list, p)
				end
			end
		end
	end
	return list
end

-- [[ Helper: Inject Packages into Runner Args ]] --
local function inject_packages_into_args(cmd, args, pkgs)
	if #pkgs == 0 then
		return args
	end

	local new_args = vim.deepcopy(args)
	local existing = {}

	for i, a in ipairs(new_args) do
		if a == "--with" and new_args[i + 1] then
			for p in new_args[i + 1]:gmatch("[^,%s]+") do
				existing[p] = true
			end
		elseif a:match("^%-%-with=(.+)$") then
			local with_val = a:match("^%-%-with=(.+)$")
			for p in with_val:gmatch("[^,%s]+") do
				existing[p] = true
			end
		end
	end

	local dash_dash_idx = nil
	for i, a in ipairs(new_args) do
		if a == "--" then
			dash_dash_idx = i
			break
		end
	end

	for _, p in ipairs(pkgs) do
		if not existing[p] then
			if dash_dash_idx then
				table.insert(new_args, dash_dash_idx, "--with")
				table.insert(new_args, dash_dash_idx + 1, p)
				dash_dash_idx = dash_dash_idx + 2
			elseif new_args[1] == "run" then
				table.insert(new_args, 2, "--with")
				table.insert(new_args, 3, p)
			else
				table.insert(new_args, "--with")
				table.insert(new_args, p)
			end
			existing[p] = true
		end
	end

	return new_args
end

-- [[ Helper: Construct Command ]] --
local function get_repl_command(opts)
	opts = opts or {}
	local ft = opts.ft or vim.bo.filetype
	local def = config.repls and config.repls[ft]

	-- 1. Check for explicit command override in opts
	if opts.cmd then
		local explicit_cmd = opts.cmd
		if type(explicit_cmd) == "function" then
			explicit_cmd = explicit_cmd()
		end
		explicit_cmd = tostring(explicit_cmd)
		if opts.args then
			local resolved_args = {}
			if type(opts.args) == "table" then
				for _, arg in ipairs(opts.args) do
					if type(arg) == "function" then
						table.insert(resolved_args, tostring(arg()))
					else
						table.insert(resolved_args, tostring(arg))
					end
				end
			elseif type(opts.args) == "string" and opts.args ~= "" then
				resolved_args = vim.split(opts.args, "%s+", { trimempty = true })
			end
			if #resolved_args > 0 then
				explicit_cmd = explicit_cmd .. " " .. table.concat(resolved_args, " ")
			end
		end
		if explicit_cmd:match("ipython") then
			ensure_ipython_profile()
		end
		return explicit_cmd
	end

	-- 2. If no config for this filetype, fallback to default shell
	if not def then
		return vim.o.shell
	end

	-- 3. Handle Side Effects
	if def.ensure_ipython_profile then
		ensure_ipython_profile()
	end

	-- 4. Check for Virtual Environment
	local venv_detected = false
	if def.detect_venv ~= false then
		venv_detected = M.has_venv()
	end

	-- 5. Select cmd and args
	local cmd = def.cmd
	local args = opts.args or def.args or {}

	if not venv_detected then
		if def.no_venv_cmd then
			cmd = def.no_venv_cmd
		end
		if def.no_venv_args and not opts.args then
			args = def.no_venv_args
		end
	end

	if type(cmd) == "function" then
		cmd = cmd()
	end

	if type(args) == "function" then
		args = args()
	end

	-- 6. Collect packages
	local pkgs = {}
	if opts.packages then
		pkgs = parse_packages(opts.packages)
	elseif not venv_detected then
		local fallback_pkgs = def.no_venv_packages or def.default_packages
		if fallback_pkgs then
			pkgs = parse_packages(fallback_pkgs)
		end
		if #pkgs > 0 and not opts.silent then
			vim.notify("Starting REPL (no venv detected, with: " .. table.concat(pkgs, ", ") .. ")", vim.log.levels.INFO)
		end
	end

	-- 7. Resolve args table
	local resolved_args = {}
	if type(args) == "table" then
		for _, arg in ipairs(args) do
			if type(arg) == "function" then
				table.insert(resolved_args, tostring(arg()))
			else
				table.insert(resolved_args, tostring(arg))
			end
		end
	elseif type(args) == "string" and args ~= "" then
		resolved_args = vim.split(args, "%s+", { trimempty = true })
	end

	-- 8. Inject packages if any
	if #pkgs > 0 then
		resolved_args = inject_packages_into_args(cmd, resolved_args, pkgs)
	end

	local cmd_parts = { tostring(cmd) }
	for _, arg in ipairs(resolved_args) do
		table.insert(cmd_parts, arg)
	end

	return table.concat(cmd_parts, " ")
end

M.get_repl_command = get_repl_command

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

	local orig_ft = vim.bo.filetype
	vim.cmd("terminal " .. cmd)
	local term_buf = vim.api.nvim_get_current_buf()
	vim.b[term_buf].send_to_repl = true
	vim.b[term_buf].send_to_repl_ft = orig_ft
	vim.b[term_buf].send_to_repl_cmd = cmd

	return term_buf
end

-- [[ Helper: Find or Create Terminal ]] --
local function get_repl_job_id(opts)
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
	local cmd = get_repl_command(opts or M._last_custom_opts)
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
	local has_custom_cmd = M._last_custom_opts and M._last_custom_opts.cmd ~= nil

	if is_new and not is_configured and not has_custom_cmd then
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

--- Start or restart REPL with custom options
---@param opts? { packages?: string|string[], cmd?: string, args?: string[]|string, prompt?: boolean, ft?: string, silent?: boolean, reset?: boolean }
function M.start_repl(opts)
	opts = opts or {}

	if opts.reset then
		M._last_custom_opts = nil
		opts = {}
	end

	if opts.prompt then
		local ft = opts.ft or vim.bo.filetype
		local def = config.repls and config.repls[ft]
		local default_val = ""
		local fallback_pkgs = def and (def.no_venv_packages or def.default_packages)
		if fallback_pkgs then
			local parsed = parse_packages(fallback_pkgs)
			default_val = table.concat(parsed, " ")
		end

		vim.ui.input({
			prompt = "Extra packages for REPL (e.g. pandas, polars): ",
			default = default_val,
		}, function(input)
			if input == nil then
				return
			end
			local trimmed = vim.trim(input)
			local new_opts = vim.tbl_extend("force", {}, opts)
			new_opts.prompt = false
			new_opts.packages = trimmed
			M.start_repl(new_opts)
		end)
		return
	end

	if opts.prompt_cmd then
		local default_cmd = ""
		if M._last_custom_opts and M._last_custom_opts.cmd then
			local last_cmd = M._last_custom_opts.cmd
			if type(last_cmd) == "function" then
				last_cmd = last_cmd()
			end
			default_cmd = tostring(last_cmd)
		else
			-- Try to detect local virtual environment executables
			local has_v, venv_path = M.has_venv()
			if has_v and venv_path then
				if vim.fn.isdirectory(venv_path) == 0 then
					venv_path = vim.fs.dirname(venv_path)
				end
				local cwd = uv.cwd() or vim.fn.getcwd()
				cwd = vim.fs.normalize(cwd)
				local candidates = {
					venv_path .. "/bin/ipython",
					venv_path .. "/bin/python",
					venv_path .. "/bin/ptpython",
					venv_path .. "/Scripts/ipython.exe",
					venv_path .. "/Scripts/python.exe",
				}
				for _, candidate in ipairs(candidates) do
					if vim.fn.executable(candidate) == 1 then
						local norm = vim.fs.normalize(candidate)
						if vim.startswith(norm, cwd .. "/") then
							default_cmd = norm:sub(#cwd + 2)
						else
							default_cmd = norm
						end
						if default_cmd:match("python$") or default_cmd:match("python%.exe$") then
							default_cmd = default_cmd .. " -i"
						end
						break
					end
				end
			end

			if default_cmd == "" then
				default_cmd = get_repl_command({ ft = opts.ft, silent = true })
			end
		end

		vim.ui.input({
			prompt = "Custom REPL command: ",
			default = default_cmd,
			completion = "shellcmd",
		}, function(input)
			if input == nil then
				return
			end
			local trimmed = vim.trim(input)
			if trimmed == "" then
				return
			end
			local new_opts = vim.tbl_extend("force", {}, opts)
			new_opts.prompt_cmd = false
			new_opts.cmd = trimmed
			M.start_repl(new_opts)
		end)
		return
	end

	M._last_custom_opts = opts

	-- Notify user if packages or custom command are explicitly specified
	if opts.packages and not opts.silent then
		local p_list = parse_packages(opts.packages)
		if #p_list > 0 then
			vim.notify("Starting REPL with packages: " .. table.concat(p_list, ", "), vim.log.levels.INFO)
		end
	elseif opts.cmd and not opts.silent then
		local cmd_str = type(opts.cmd) == "function" and opts.cmd() or opts.cmd
		vim.notify("Starting REPL with command: " .. tostring(cmd_str), vim.log.levels.INFO)
	end

	-- If REPL already exists, kill it so we can start fresh with new opts/command
	local term_buf, _ = find_existing_repl()
	if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
		local job_id = vim.b[term_buf].terminal_job_id
		if job_id then
			pcall(vim.fn.jobstop, job_id)
		end
		pcall(vim.api.nvim_buf_delete, term_buf, { force = true })
	end

	local job_id, _, new_term_buf = get_repl_job_id(opts)
	return job_id, new_term_buf
end

--- Start or restart REPL with a custom command (prompts if nil or empty)
---@param custom_cmd? string|fun():string
---@param opts? table
function M.start_repl_cmd(custom_cmd, opts)
	opts = opts or {}
	if not custom_cmd or custom_cmd == "" then
		opts.prompt_cmd = true
		return M.start_repl(opts)
	else
		opts.cmd = custom_cmd
		return M.start_repl(opts)
	end
end
M.start_repl_command = M.start_repl_cmd

--- Start or restart REPL with extra packages (prompts if nil or empty)
---@param packages? string|string[]
---@param opts? table
function M.start_repl_with(packages, opts)
	opts = opts or {}
	if not packages or packages == "" or (type(packages) == "table" and #packages == 0) then
		opts.prompt = true
		return M.start_repl(opts)
	else
		opts.packages = packages
		return M.start_repl(opts)
	end
end

--- Restart the REPL process (re-using last custom options if any)
---@param opts? table
function M.restart_repl(opts)
	return M.start_repl(opts or M._last_custom_opts or {})
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
	cmd("SendToReplWith", function(opts)
		local raw_input = vim.trim(opts.args or "")
		if raw_input == "" then
			M.start_repl({ prompt = true })
		else
			M.start_repl({ packages = raw_input })
		end
	end, {
		nargs = "*",
		complete = function(arg_lead)
			local common = {
				"pandas",
				"numpy",
				"polars",
				"scipy",
				"matplotlib",
				"seaborn",
				"scikit-learn",
				"requests",
				"torch",
				"torchvision",
				"duckdb",
				"sympy",
				"statsmodels",
				"openpyxl",
				"pyarrow",
				"fastapi",
				"httpx",
				"rich",
				"tqdm",
				"jupyter",
				"pydantic",
				"altair",
				"bokeh",
				"plotly",
			}
			local matches = {}
			for _, pkg in ipairs(common) do
				if vim.startswith(pkg, arg_lead) then
					table.insert(matches, pkg)
				end
			end
			return matches
		end,
		desc = "Start or restart REPL with specified packages (e.g. :SendToReplWith pandas polars)",
	})
	local function complete_repl_cmd(arg_lead)
		local suggestions = {}
		local seen = {}

		local function add(item)
			if item and item ~= "" and not seen[item] then
				seen[item] = true
				table.insert(suggestions, item)
			end
		end

		-- Check virtual environments for executables
		local has_v, venv_path = M.has_venv()
		if has_v and venv_path then
			if vim.fn.isdirectory(venv_path) == 0 then
				venv_path = vim.fs.dirname(venv_path)
			end
			local cwd = uv.cwd() or vim.fn.getcwd()
			cwd = vim.fs.normalize(cwd)
			local candidates = {
				venv_path .. "/bin/ipython",
				venv_path .. "/bin/python",
				venv_path .. "/bin/ptpython",
				venv_path .. "/Scripts/ipython.exe",
				venv_path .. "/Scripts/python.exe",
			}
			for _, c in ipairs(candidates) do
				if vim.fn.executable(c) == 1 then
					local norm = vim.fs.normalize(c)
					local rel = norm
					if vim.startswith(norm, cwd .. "/") then
						rel = norm:sub(#cwd + 2)
					end
					if vim.startswith(rel, arg_lead) then
						add(rel)
					end
				end
			end
		end

		-- Shell commands
		for _, item in ipairs(vim.fn.getcompletion(arg_lead, "shellcmd")) do
			add(item)
		end

		-- Files
		for _, item in ipairs(vim.fn.getcompletion(arg_lead, "file")) do
			add(item)
		end

		return suggestions
	end

	local function handle_custom_cmd(opts)
		local raw_cmd = vim.trim(opts.args or "")
		if raw_cmd == "" then
			M.start_repl({ prompt_cmd = true })
		else
			M.start_repl({ cmd = raw_cmd })
		end
	end

	cmd("SendToReplCmd", handle_custom_cmd, {
		nargs = "*",
		complete = complete_repl_cmd,
		desc = "Start or restart REPL with custom command (e.g. :SendToReplCmd .venv/bin/ipython)",
	})
	cmd("SendToReplCommand", handle_custom_cmd, {
		nargs = "*",
		complete = complete_repl_cmd,
		desc = "Start or restart REPL with custom command (alias for :SendToReplCmd)",
	})
	cmd("SendToReplStart", handle_custom_cmd, {
		nargs = "*",
		complete = complete_repl_cmd,
		desc = "Start or restart REPL with custom command (prompts if empty)",
	})
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

