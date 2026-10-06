--!strict

--[[ 
    @author: @skaterstudios
    @description: A lightweight utility module to manage and cleanup
    resources like functions, connections, threads, and instances.
]]

export type Pocket = {
	items: {any},
	add: <I> (self: Pocket, item: I) -> I,
	destroy: (self: Pocket) -> (),
}

local Pocket = {}
Pocket.__index = Pocket

function Pocket.new()
	local self = setmetatable({}, Pocket)

	self.items = {}

	return self
end

function Pocket:add<I>(item: I) : I
	table.insert(self.items, item)

	return item
end

function Pocket.destroy(self)
	for _, item in self.items do
		if typeof(item) == "function" then
			item()
		elseif typeof(item) == "thread" then
			pcall(function()
				task.cancel(item)
			end)
		elseif typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		elseif typeof(item) == "Instance" then
			item:Destroy()
		elseif typeof(item) == "table" then
			if typeof((item :: any).destroy) == "function" then
				(item :: any):destroy()
			end
		end
	end
	table.clear(self.items)
end

return Pocket