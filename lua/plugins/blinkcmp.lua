Later(function()
	vim.pack.add({
		{ src = "https://github.com/saghen/blink.lib" },
		{ src = "https://github.com/saghen/blink.cmp" },
		{ src = "https://github.com/rafamadriz/friendly-snippets" },
		{ src = "https://github.com/L3MON4D3/LuaSnip", version = vim.version.range("^2") },
	})

	local capabilities = vim.lsp.protocol.make_client_capabilities()

	capabilities = vim.tbl_deep_extend("force", capabilities, require("blink.cmp").get_lsp_capabilities({}, false))

	capabilities = vim.tbl_deep_extend("force", capabilities, {
		textDocument = {
			foldingRange = {
				dynamicRegistration = false,
				lineFoldingOnly = true,
			},
		},
	})

	vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
	vim.api.nvim_set_hl(0, "FloatBorder", { bg = "NONE" })
	vim.api.nvim_set_hl(0, "StatusLine", { bg = "NONE" })
	vim.api.nvim_set_hl(0, "StatusLineNC", { bg = "NONE" })

	require("blink.cmp").setup({
		snippets = { preset = "luasnip" },
		keymap = {
			preset = "none",
			["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
			["<Tab>"] = {
				function(cmp)
					if cmp.snippet_active() then
						return cmp.accept()
					else
						local has_words_before = function()
							local col = vim.api.nvim_win_get_cursor(0)[2]
							if col == 0 then
								return false
							end
							local line = vim.api.nvim_get_current_line()
							return line:sub(col, col):match("%s") == nil
						end

						return cmp.select_next({ auto_insert = has_words_before() })
					end
				end,
				"snippet_forward",
				"fallback",
			},
			["<S-Tab>"] = {
				function(cmp)
					if cmp.snippet_active() then
						return cmp.snippet_backward()
					else
						return cmp.select_prev()
					end
				end,
				"fallback",
			},
			["<CR>"] = { "accept", "fallback" },
			["<C-u>"] = {
				"scroll_documentation_up",
				"fallback",
			},
			["<C-d>"] = {
				"scroll_documentation_down",
				"fallback",
			},
			["<Up>"] = { "select_prev", "fallback" },
			["<Down>"] = { "select_next", "fallback" },
			["<C-p>"] = { "select_prev", "fallback_to_mappings" },
			["<C-n>"] = { "select_next", "fallback_to_mappings" },
			["<C-N>"] = { "select_next", "show" },
			["<C-P>"] = { "select_prev", "show" },
			["<C-J>"] = { "select_next", "fallback" },
			["<C-K>"] = { "select_prev", "fallback" },
			["<C-U>"] = { "scroll_documentation_up", "fallback" },
			["<C-D>"] = { "scroll_documentation_down", "fallback" },
			["<C-e>"] = { "hide", "fallback" },
		},

		appearance = {
			use_nvim_cmp_as_default = true,
			nerd_font_variant = "mono",
			kind_icons = require("icons").kind2,
		},

		completion = {
			accept = { auto_brackets = { enabled = true } },
			menu = {
				min_width = 25, -- Memastikan lebar popup memadai
				direction_priority = { "s", "n" },
				border = "rounded",
				winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:CursorLine,Search:None",
				draw = {
					padding = { 0, 3 }, -- 0 spasi di kiri, 1 spasi di kanan
					gap = 2, -- Menambah spasi antar kolom agar teks tidak menumpuk
					treesitter = { "lsp" },
					columns = {
						{ "kind_icon" },
						{ "label", "label_description", gap = 3 },
						{ "kind" },
					},
					components = {
						kind_icon = {
							text = function(ctx)
								return ctx.kind_icon
							end,
						},
						kind = {
							ellipsis = false, -- Mencegah pemotongan string 'Snippet' menjadi 'Snippe'
						},
					},
				},
			},
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 0,
				window = {
					border = "rounded",
					winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:CursorLine,Search:None",
					direction_priority = {
						menu_north = { "e", "w" },
						menu_south = { "e", "w" },
					},
				},
			},
			ghost_text = {
				enabled = true,
			},
		},

		signature = {
			enabled = true,
			window = { border = "rounded" },
		},
		cmdline = {
			keymap = { preset = "inherit" },
			completion = { menu = { auto_show = true } },
		},

		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},

		fuzzy = {
			implementation = "lua",
		},
	})

	-- :config snippets
	require("luasnip.loaders.from_vscode").lazy_load()
	-- :config custom snippets
	local lpath = vim.fn.stdpath("config") .. "/snippets"
	require("luasnip.loaders.from_vscode").lazy_load({ paths = lpath })
	require("luasnip.loaders.from_vscode").load({ paths = lpath })
end)
