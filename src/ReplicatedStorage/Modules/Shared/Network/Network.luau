local RunService = game:GetService("RunService")

local namespace = require(script.Parent.namespace)

local Network = {}

function Network.Fire(data : {}, networkType : string, player : Player?)
	if not namespace[networkType] and not networkType:match("AllClients") then
		warn("network type not found")
		
		return
	end
	
	if networkType:match("Vfx") then
		namespace["Vfx"].sendToAll(data)
		return
	end
	
	if networkType:match("ComboClient") then
		namespace["ComboClient"].sendToAll(data)
		return
	end
	
	if networkType:match("Ragdoll") then
		namespace["Ragdoll"].sendToAll(data)
	end
	
	if RunService:IsClient() then
		namespace[networkType].send(data)
	end	
	
	if RunService:IsServer() then
		namespace[networkType].sendTo(data, player)
	end
end

return Network