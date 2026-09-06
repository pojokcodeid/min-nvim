local dashboard_cleaner = vim.api.nvim_create_augroup("DashboardCleaner", { clear = true })

-- Buat highlight group khusus yang transparan untuk kursor dashboard
vim.api.nvim_set_hl(0, "HiddenCursor", { blend = 100, nocombine = true })

-- Fungsi untuk cek apakah buffer saat ini adalah dashboard
local function is_dashboard()
    return vim.bo.filetype == "" or vim.bo.filetype == "alpha" or vim.bo.filetype == "dashboard"
end

-- 1. Atur UI saat masuk ke buffer (Dashboard atau Netrw)
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    group = dashboard_cleaner,
    callback = function()
        local ft = vim.bo.filetype

        if is_dashboard() then
            -- Setelan bersih total untuk Dashboard
            vim.opt.laststatus = 0
            vim.opt_local.number = false
            vim.opt_local.relativenumber = false
            vim.opt_local.signcolumn = "no"
            vim.opt_local.foldcolumn = "0"
            vim.opt.guicursor = "a:HiddenCursor-blinkwait0"

        elseif ft == "netrw" then
            -- Setelan khusus Netrw (Hanya hilangkan numbering, kursor & statusline tetap ada)
            vim.opt_local.number = false
            vim.opt_local.relativenumber = false
            -- Kembalikan kursor ke normal agar bisa bernavigasi di netrw
            vim.opt.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,sm:block-blinkwait175-blinkoff150-blinkon175"
            vim.opt.laststatus = 3 -- Tetap munculkan statusline agar tahu posisi folder (bisa diubah ke 0 jika ingin disembunyikan juga)

        else
            -- KEMBALIKAN KE SETTINGAN NORMAL UTK FILE BIASA
            vim.opt.laststatus = 3
            vim.opt_local.number = true
            vim.opt_local.relativenumber = true
            vim.opt_local.signcolumn = "yes"
            vim.opt.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,sm:block-blinkwait175-blinkoff150-blinkon175"
        end
    end,
})

-- 2. MUNCULKAN KURSOR SEBAGAI 'BAR' SAAT MASUK COMMAND MODE
vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = dashboard_cleaner,
    callback = function()
        if is_dashboard() then
            vim.opt.guicursor = "c:ver25" 
        end
    end
})

-- 3. SEMBUNYIKAN LAGI KURSOR SAAT KELUAR DARI COMMAND MODE
vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = dashboard_cleaner,
    callback = function()
        if is_dashboard() then
            vim.opt.guicursor = "a:HiddenCursor-blinkwait0"
        end
    end
})

-- 4. Kembalikan kursor terminal saat keluar Neovim
vim.api.nvim_create_autocmd("VimLeave", {
    group = dashboard_cleaner,
    callback = function()
        vim.opt.guicursor = "a:block"
    end,
})

-- Highlight selection on yank
vim.api.nvim_create_autocmd("TextYankPost", {
	group = vim.api.nvim_create_augroup("highlight_yank", { clear = true }),
	pattern = "*",
	desc = "highlight selection on yank",
	callback = function()
		vim.highlight.on_yank({ timeout = 200, visual = true })
	end,
})

-- Restore cursor to file position in previous editing session
vim.api.nvim_create_autocmd("BufReadPost", {
	callback = function(args)
		local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
		local line_count = vim.api.nvim_buf_line_count(args.buf)
		if mark[1] > 0 and mark[1] <= line_count then
			vim.api.nvim_win_set_cursor(0, mark)
			-- defer centering slightly so it's applied after render
			vim.schedule(function()
				vim.cmd("normal! zz")
			end)
		end
	end,
})

