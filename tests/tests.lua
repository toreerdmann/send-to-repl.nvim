local helpers = require("tests.test_helpers")
local plugin = require("send-to-repl") -- Ensure this matches your require string!

describe("REPL Simple Tests", function()
	after_each(function()
		helpers.cleanup_terminals()
	end)

	it("basic test for python", function()
		vim.wait(5000)

		-- 1. Setup
		local buf = helpers.create_test_buffer({ "print(1 + 1)" })

		vim.wait(2000)

		-- 2. Trigger Plugin (Send current line)
		-- Adjust this call to match your plugin's actual API for sending lines
		plugin.send_line()

		-- 3. Assert
		local success = helpers.expect_repl_output("2", 1000)
		assert.is_true(success, "Failed to find '2' in REPL output")
		print("Test 1 succeded")
		--
		-- Add this where you want to debug the REPL state
		local bufs = vim.api.nvim_list_bufs()
		for _, buf in ipairs(bufs) do
			if vim.bo[buf].buftype == "terminal" then
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				print("\n--- REPL BUFFER CONTENT ---")
				for i, line in ipairs(lines) do
					print(string.format("%02d: %s", i, line))
				end
				print("---------------------------\n")
			end
		end

		-- remove code
		vim.cmd("normal! ggVGd")

		-- add new content
		local content = {
			"def add_one(x):",
			"",
			"    return x + 1",
		}
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
		vim.wait(500)
		vim.cmd("normal! ggVG")
		plugin.send_visual()
		vim.wait(500)

		-- add new content
		vim.cmd("normal! ggVGd")
		content = {
			"print(add_one(1))",
		}
		vim.api.nvim_buf_set_lines(buf, 5, -1, false, content)
		vim.wait(500)
		vim.cmd("normal! ggVG")
		plugin.send_visual()
		vim.wait(500)

		success = helpers.expect_repl_output("2", 3000)
		assert.is_true(success, "Multi-line block failed. See DEBUG output above.")
		print("Test 2 succeded")

		-- Add this where you want to debug the REPL state
		local bufs = vim.api.nvim_list_bufs()
		for _, buf in ipairs(bufs) do
			if vim.bo[buf].buftype == "terminal" then
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				print("\n--- REPL BUFFER CONTENT ---")
				for i, line in ipairs(lines) do
					print(string.format("%02d: %s", i, line))
				end
				print("---------------------------\n")
			end
		end
	end)
end)
