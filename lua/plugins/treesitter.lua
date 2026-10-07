return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		event = "VeryLazy",
		cmd = {
			"TSInstall",
			"TSInstallSync",
			"TSUpdate",
			"TSUpdateSync",
			"TSUninstall",
			"TSUninstallInfo",
			"TSInstallFromGrammar",
		},
		build = ":TSUpdate",
		config = function()
			-- daftarkan parser custom CFML SEBELUM :TSUpdate dipanggil
			vim.api.nvim_create_autocmd("User", {
				pattern = "TSUpdate",
				callback = function()
					local parsers = require("nvim-treesitter.parsers")

					parsers.cfml = {
						install_info = {
							url = "https://github.com/cfmleditor/tree-sitter-cfml",
							location = "cfml",
							files = { "src/parser.c", "src/scanner.c" },
							branch = "master",
						},
					}

					parsers.cfscript = {
						install_info = {
							url = "https://github.com/cfmleditor/tree-sitter-cfml",
							location = "cfscript",
							files = { "src/parser.c", "src/scanner.c" },
							branch = "master",
						},
					}
				end,
			})
			local ts = require("nvim-treesitter")
			ts.setup({})

			-- install parser yang dibutuhkan
			ts.install({
				"lua",
				"luadoc",
				"printf",
				"vim",
				"vimdoc",
				"javascript",
				"typescript",
				"tsx",
				"html",
				"cfml",
				"cfscript",
				"sql",
			})

			local ts_filetypes = ts.get_installed(true)
			-- filetype yang PUNYA query indent lengkap (bukan cfml/cfscript)
			local keys_to_delete = { "cfml", "cfscript" }
			local ts_indent_filetypes = {}
			for _, key in ipairs(keys_to_delete) do
				if ts_filetypes[key] ~= nil then
					ts_indent_filetypes[key] = ts_filetypes[key]
				end
			end

			-- highlight
			vim.api.nvim_create_autocmd("FileType", {
				pattern = ts_filetypes,
				callback = function()
					pcall(vim.treesitter.start)
				end,
			})

			-- indent
			vim.api.nvim_create_autocmd("FileType", {
				pattern = ts_indent_filetypes,
				callback = function()
					vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end,
			})

			-- untuk cfml/cfscript, pastikan pakai autoindent bawaan Vim
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "cfml", "cfscript" },
				callback = function()
					vim.bo.autoindent = true
					vim.bo.indentexpr = "" -- kosongkan, biar fallback ke autoindent biasa
				end,
			})

			-- fold
			vim.api.nvim_create_autocmd("FileType", {
				pattern = ts_filetypes,
				callback = function()
					vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
					vim.wo[0][0].foldmethod = "expr"
				end,
			})

			vim.api.nvim_create_user_command("TSInstallInfo", function()
				local ts = require("nvim-treesitter")
				local pickers = require("telescope.pickers")
				local finders = require("telescope.finders")
				local conf = require("telescope.config").values
				local actions = require("telescope.actions")
				local action_state = require("telescope.actions.state")

				local function build_results()
					local installed = {}
					for _, lang in ipairs(ts.get_installed()) do
						installed[lang] = true
					end

					local results = {}
					for _, lang in ipairs(ts.get_available()) do
						table.insert(results, { lang = lang, installed = installed[lang] or false })
					end

					-- yang sudah ter-install tampil di atas
					table.sort(results, function(a, b)
						if a.installed ~= b.installed then
							return a.installed
						end
						return a.lang < b.lang
					end)
					return results
				end

				local function make_finder()
					return finders.new_table({
						results = build_results(),
						entry_maker = function(e)
							return {
								value = e,
								ordinal = e.lang,
								display = (e.installed and "✓ " or "  ") .. e.lang,
							}
						end,
					})
				end

				pickers
					.new({}, {
						prompt_title = "Treesitter Parsers (Enter: install / uninstall)",
						finder = make_finder(),
						sorter = conf.generic_sorter({}),
						attach_mappings = function(bufnr)
							actions.select_default:replace(function()
								local sel = action_state.get_selected_entry()
								if not sel then
									return
								end
								local lang = sel.value.lang

								actions.close(bufnr)

								-- cek ulang status terkini, bukan dari hasil yang mungkin sudah usang
								local is_installed = vim.list_contains(ts.get_installed(), lang)

								if is_installed then
									vim.notify("Uninstalling parser: " .. lang, vim.log.levels.INFO)
									ts.uninstall({ lang }):await(function()
										vim.notify("Parser uninstalled: " .. lang, vim.log.levels.INFO)
									end)
								else
									vim.notify("Installing parser: " .. lang, vim.log.levels.INFO)
									ts.install({ lang }):await(function()
										vim.notify("Parser installed: " .. lang, vim.log.levels.INFO)
									end)
								end
							end)
							return true
						end,
					})
					:find()
			end, {})
		end,
	},
	-- filetype detection CFML
	{
		"nvim-lua/plenary.nvim",
		event = "VeryLazy",
		config = function()
			vim.filetype.add({
				extension = {
					cfm = "cfml",
					cfml = "cfml",
					cfc = "cfml",
					sfc = "cfml",
					cfs = "cfscript",
				},
			})
		end,
	},
}