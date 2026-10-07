require("vim._core.ui2").enable({})
vim.pack.add({ "https://github.com/rachartier/tiny-cmdline.nvim" })
vim.o.cmdheight = 0
require("tiny-cmdline").setup({
	width = {
		value = "70%",
		min = 40,
		max = 100,
	},

	position = {
		x = "50%",
		y = "50%",
	},

	border = "rounded",

	-- ini hanya horizontal
	menu_col_offset = 1,
	on_reposition = require("tiny-cmdline").adapters.blink,
	-- native_types = {},
})
