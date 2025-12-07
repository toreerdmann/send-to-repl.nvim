local M = {}

-- Create a fresh buffer with Python content
function M.create_test_buffer(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "filetype", "python")
	vim.api.nvim_set_current_buf(buf)
	return buf
end

-- Wait until the terminal buffer contains actual text (is not empty)
function M.wait_for_boot(timeout_ms)
	local timeout = timeout_ms or 5000
	local start = vim.loop.hrtime()

	local ready = vim.wait(timeout, function()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.bo[buf].buftype == "terminal" then
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				-- Check if there is meaningful content (more than just empty lines)
				for _, line in ipairs(lines) do
					if #line > 0 then
						return true
					end
				end
			end
		end
		return false
	end)

	if not ready then
		print("ERROR: REPL did not start within " .. timeout .. "ms")
	end
end

-- Cleanup: Kill all terminal buffers
function M.cleanup_terminals()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buftype == "terminal" then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
	-- Small wait to allow process to detach
	vim.wait(50)
end

function M.send_newline_to_repl()
	vim.wait(100)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buftype == "terminal" then
			local chan = vim.b[buf].terminal_job_id
			if chan then
				-- Use \r (Carriage Return) which is often more reliable than \n for Enter
				vim.api.nvim_chan_send(chan, "\r")
			end
			break
		end
	end
end

function M.expect_repl_output(pattern, timeout_ms)
	local timeout = timeout_ms or 2000
	local found = false
	local final_lines = {} -- Store lines for debugging

	vim.wait(timeout, function()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.bo[buf].buftype == "terminal" then
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				final_lines = lines -- Capture current state
				for _, line in ipairs(lines) do
					if string.find(line, pattern, 1, true) then
						found = true
						return true
					end
				end
			end
		end
		return false
	end)

	-- IF FAILED: Print what was actually in the REPL
	if not found then
		print("\n--- DEBUG: REPL CONTENT START ---")
		for i, line in ipairs(final_lines) do
			print(string.format("%02d: %s", i, line))
		end
		print("--- DEBUG: REPL CONTENT END ---\n")
	end

	return found
end

return M
