local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Modules.Shared

local ByteNet = require(Shared.ByteNet)

local baseData = {
	module = ByteNet.string,
	method = ByteNet.string,
	msg = ByteNet.string,
	animLength = ByteNet.float32
}

return ByteNet.defineNamespace("Network", function()
	return {
		Core = ByteNet.definePacket({
			value = ByteNet.struct(baseData)
		}),
		
		Vfx = ByteNet.definePacket({
			value = ByteNet.struct({
				module = ByteNet.string,
				method = ByteNet.string,
				msg = ByteNet.string,
				animLength = ByteNet.float32,
				player = ByteNet.inst
			})
		}),
		
		Ragdoll = ByteNet.definePacket({
			value = ByteNet.struct({
				character = ByteNet.inst,
				msg = ByteNet.string,
			})
		}),
		
		Hitbox = ByteNet.definePacket({
			value = ByteNet.struct({
				module = ByteNet.string,
				method = ByteNet.string,
				msg = ByteNet.string,
				hits = ByteNet.array(ByteNet.inst)
			})
		}),
		
		Client = ByteNet.definePacket({
			value = ByteNet.struct({
				module = ByteNet.string,
				method = ByteNet.string,
				msg = ByteNet.string,
				animLength = ByteNet.float32,
				character = ByteNet.inst
			})
		}),
		
		ComboClient = ByteNet.definePacket({
			value = ByteNet.struct({
				module = ByteNet.string,
				method = ByteNet.string,
				character2 = ByteNet.inst,
				animLength = ByteNet.float32,
				character = ByteNet.inst
			})
		})
	}
end)

