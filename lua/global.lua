--[[
vim.pack.add({ "https://github.com/nvim-mini/mini.misc" })
local misc = require("mini.misc")
_G.Later = function(f)
	misc.safely("later", f)
end
_G.On_event = function(ev, f)
	if type(ev) == "table" then
		for _, v in pairs(ev) do
			misc.safely("event:" .. v, f)
		end
	else
		misc.safely("event:" .. ev, f)
	end
end
]]
--
