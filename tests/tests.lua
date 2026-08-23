local helpers = require("tests.test_helpers")
local plugin = require("send-to-repl")

describe("send-to-repl tests", function()
	after_each(function()
		helpers.cleanup_terminals()
	end)

	it("send_line executes python expressions", function()
		local buf = helpers.create_test_buffer({ "print(10 + 20)" })
		plugin.send_line()
		local success = helpers.expect_repl_output("30", 5000)
		assert.is_true(success, "Failed to find '30' in REPL output for send_line")
	end)

	it("send_word sends word under cursor without modifying registers", function()
		vim.fn.setreg("v", "KEEP_ME")
		local buf = helpers.create_test_buffer({ "my_var = 42", "print(my_var)" })
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		plugin.send_line()
		helpers.expect_repl_output("my_var", 3000)

		vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- cursor on my_var
		plugin.send_word()
		local success = helpers.expect_repl_output("42", 5000)
		assert.is_true(success, "Failed to find '42' in REPL output for send_word")
		assert.are.same("KEEP_ME", vim.fn.getreg("v"), "Register 'v' should not be modified")
	end)

	it("send_paragraph sends paragraph without modifying registers", function()
		vim.fn.setreg("v", "KEEP_ME")
		local content = {
			"def multiply(a, b):",
			"    return a * b",
			"",
			"print(multiply(3, 4))",
		}
		local buf = helpers.create_test_buffer(content)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		plugin.send_paragraph()

		vim.api.nvim_win_set_cursor(0, { 4, 0 })
		plugin.send_line()

		local success = helpers.expect_repl_output("12", 5000)
		assert.is_true(success, "Failed to find '12' in REPL output for send_paragraph")
		assert.are.same("KEEP_ME", vim.fn.getreg("v"), "Register 'v' should not be modified")
	end)

	it("send_cell executes code within '# %%' cell boundaries", function()
		local content = {
			"# %% Setup cell",
			"x = 100",
			"# %% Calculation cell",
			"y = x * 2",
			"print(f'Cell result: {y}')",
			"# %% Next cell",
			"z = 999",
		}
		local buf = helpers.create_test_buffer(content)
		-- Execute first cell
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		plugin.send_cell()

		-- Execute second cell
		vim.api.nvim_win_set_cursor(0, { 4, 0 })
		plugin.send_cell()

		local success = helpers.expect_repl_output("Cell result: 200", 5000)
		assert.is_true(success, "Failed to find cell result in REPL output")
	end)

	it("send_file executes entire buffer", function()
		local content = {
			"a = 5",
			"b = 7",
			"print(f'Sum: {a + b}')",
		}
		local buf = helpers.create_test_buffer(content)
		plugin.send_file()

		local success = helpers.expect_repl_output("Sum: 12", 5000)
		assert.is_true(success, "Failed to find 'Sum: 12' in REPL output for send_file")
	end)

	it("send_range sends specific line numbers", function()
		local content = {
			"ignore_me = 1",
			"active_val = 88",
			"print(f'Active: {active_val}')",
			"ignore_too = 9",
		}
		local buf = helpers.create_test_buffer(content)
		plugin.send_range(2, 3)

		local success = helpers.expect_repl_output("Active: 88", 5000)
		assert.is_true(success, "Failed to find 'Active: 88' in REPL output for send_range")
	end)

	it("send_raw and send send custom text directly", function()
		helpers.create_test_buffer({ "" })
		plugin.send("print('Hello from send()')")
		local success = helpers.expect_repl_output("Hello from send()", 5000)
		assert.is_true(success, "Failed to find custom text in REPL output")
	end)

	it("registers user commands", function()
		local commands = vim.api.nvim_get_commands({})
		assert.is_not_nil(commands["SendToReplLine"])
		assert.is_not_nil(commands["SendToReplWord"])
		assert.is_not_nil(commands["SendToReplParagraph"])
		assert.is_not_nil(commands["SendToReplVisual"])
		assert.is_not_nil(commands["SendToReplCell"])
		assert.is_not_nil(commands["SendToReplFile"])
		assert.is_not_nil(commands["SendToReplToggle"])
		assert.is_not_nil(commands["SendToReplRestart"])
		assert.is_not_nil(commands["SendToReplClear"])
		assert.is_not_nil(commands["SendToReplInterrupt"])
		assert.is_not_nil(commands["SendToReplSend"])
	end)
end)

