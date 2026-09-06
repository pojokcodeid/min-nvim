_G.LAZYGIT_TOGGLE = function()
    local ok = pcall(require, "toggleterm")
    if not ok then
        require("notify")("toggleterm not found!", "error")
        return
    end
    local Terminal = require("toggleterm.terminal").Terminal
    local lazygit = Terminal:new({ cmd = "lazygit", hidden = true })
    lazygit:toggle()
end

vim.pack.add({ 'https://github.com/nvim-mini/mini.misc' })
local misc = require('mini.misc')
_G.Later = function(f) misc.safely('later', f) end
_G.On_event = function(ev, f)
    if type(ev) == "table" then
        for _, v in pairs(ev) do
            misc.safely('event:' .. v, f)
        end
    else
        misc.safely('event:' .. ev, f)
    end
end
