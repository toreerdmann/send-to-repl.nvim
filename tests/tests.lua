local helpers = require("tests.test_helpers")
local plugin = require("send-to-repl")

describe("send-to-repl tests", function()
	after_each(function()
		helpers.cleanup_terminals()
	end)

	it("send_line executes python expressions", function()
		local buf = helpers.create_test_buffer({ "print(10 + 20)" })
		plugin.send_line()
		local success = helpers.expect_repl_output("30", 10000)
		assert.is_true(success, "Failed to find '30' in REPL output for send_line")
	end)

	it("send_word sends word under cursor without modifying registers", function()
		vim.fn.setreg("v", "KEEP_ME")
		local buf = helpers.create_test_buffer({ "print(42)" })
		vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- cursor on 42
		plugin.send_word()
		local success = helpers.expect_repl_output("42", 10000)
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

		local success = helpers.expect_repl_output("12", 10000)
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
		assert.is_not_nil(commands["SendToReplWith"])
		assert.is_not_nil(commands["SendToReplStart"])
	end)

	it("has_venv correctly detects environment presence and absence", function()
		local temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")

		-- In clean temp dir without venv or project
		local detected, _ = plugin.has_venv(temp_dir)
		assert.is_false(detected, "Should not detect venv in empty directory")

		-- With .venv folder
		local venv_path = temp_dir .. "/.venv"
		vim.fn.mkdir(venv_path, "p")
		detected, _ = plugin.has_venv(temp_dir)
		assert.is_true(detected, "Should detect .venv folder")

		-- Cleanup
		vim.fn.delete(temp_dir, "rf")

		-- With VIRTUAL_ENV env variable
		local orig_venv = vim.env.VIRTUAL_ENV
		local dummy_venv = vim.fn.tempname()
		vim.fn.mkdir(dummy_venv, "p")
		vim.env.VIRTUAL_ENV = dummy_venv

		assert.is_true(plugin.has_venv(), "Should detect active VIRTUAL_ENV")

		-- Restore env
		vim.fn.delete(dummy_venv, "rf")
		vim.env.VIRTUAL_ENV = orig_venv
	end)

	it("get_repl_command includes no_venv_packages when no venv is present", function()
		plugin.setup({
			repls = {
				python = {
					no_venv_packages = { "pandas" },
				},
			},
		})

		local temp_empty = vim.fn.tempname()
		vim.fn.mkdir(temp_empty, "p")

		-- Save and temporarily clear VIRTUAL_ENV if any
		local orig_venv = vim.env.VIRTUAL_ENV
		vim.env.VIRTUAL_ENV = nil

		local cmd = plugin.get_repl_command({ ft = "python", silent = true })
		assert.is_not_nil(cmd:match("%-%-with%s+ipython"), "Command should contain --with ipython")
		assert.is_not_nil(cmd:match("%-%-with%s+pandas"), "Command should contain --with pandas")

		-- Reset
		vim.env.VIRTUAL_ENV = orig_venv
		vim.fn.delete(temp_empty, "rf")
		plugin.setup({
			repls = {
				python = {
					no_venv_packages = {},
				},
			},
		})
	end)

	it("get_repl_command supports on-demand packages", function()
		local cmd = plugin.get_repl_command({ ft = "python", packages = "pandas, polars", silent = true })
		assert.is_not_nil(cmd:match("%-%-with%s+pandas"), "Command should contain --with pandas")
		assert.is_not_nil(cmd:match("%-%-with%s+polars"), "Command should contain --with polars")
		assert.is_not_nil(cmd:match("%-%-with%s+ipython"), "Command should contain --with ipython")
	end)

	it("get_repl_command supports custom cmd override", function()
		local custom = "uv run --with pandas,ipython -- ipython"
		local cmd = plugin.get_repl_command({ cmd = custom })
		assert.are.same(custom, cmd)
	end)

	it("start_repl launches and executes in REPL with custom packages", function()
		helpers.create_test_buffer({ "print('custom_repl_ok')" })
		plugin.start_repl({ packages = "requests", silent = true })
		plugin.send_line()
		local success = helpers.expect_repl_output("custom_repl_ok", 10000)
		assert.is_true(success, "Failed to find 'custom_repl_ok' in REPL output")
	end)
end)

