--[[
	Signal

	A plain Lua event, for passing game objects between server modules.

	A BindableEvent deep copies any table it is given. That drops the
	table's metatable, so a listener gets an enemy with no methods, and it
	errors outright ("tables cannot be cyclic") as soon as the table
	points back at itself, which an enemy does the moment a Necromancer
	and its summons reference each other. This passes the arguments
	through untouched.

	It mirrors the BindableEvent shape the code already used: Fire on the
	signal, and Connect, Once and Wait on its Event, which is the signal
	itself. So swapping Instance.new("BindableEvent") for Signal.new()
	needs no change at any call site.
]]

--[[
	What connects to this

	Used by:
	  Server.Game.Enemies.EnemyBase for Died (per enemy and the shared
	  one), and Server.Game.Combat.DamageService for Damaged and
	  EnemyKilled, which all carry enemy objects.

	Each listener runs in its own thread with task.spawn, so one that
	errors or yields cannot stop the others or the code that fired it,
	the same as a BindableEvent.
]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local List = self.Signal.Listeners
	local Index = table.find(List, self)
	if Index then
		table.remove(List, Index)
	end
end

function Signal.new()
	local self = setmetatable({}, Signal)
	self.Listeners = {}
	-- BindableEvent compatibility: Signal.Event:Connect(...)
	self.Event = self
	return self
end

function Signal:Connect(Callback: (...any) -> ())
	local Conn = setmetatable({ Signal = self, Callback = Callback, Connected = true }, Connection)
	table.insert(self.Listeners, Conn)
	return Conn
end

function Signal:Once(Callback: (...any) -> ())
	local Conn
	Conn = self:Connect(function(...)
		Conn:Disconnect()
		Callback(...)
	end)
	return Conn
end

function Signal:Wait()
	local Thread = coroutine.running()
	self:Once(function(...)
		task.spawn(Thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, Conn in ipairs(table.clone(self.Listeners)) do
		if Conn.Connected then
			task.spawn(Conn.Callback, ...)
		end
	end
end

function Signal:Destroy()
	for _, Conn in ipairs(table.clone(self.Listeners)) do
		Conn:Disconnect()
	end
end

return Signal
