local RunService = game:GetService("RunService")

local CameraShake = {}
CameraShake.__index = CameraShake

local DEFAULT_INTENSITY = 0.35
local DEFAULT_DURATION = 0.2

local ActiveShakeToken = 0
local CurrentOffset = CFrame.new()

RunService:BindToRenderStep("CameraShakeApply", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = workspace.CurrentCamera
	if cam and CurrentOffset ~= CFrame.new() then
		cam.CFrame = cam.CFrame * CurrentOffset
	end
end)

function CameraShake:Shake(Intensity: number?, Duration: number?)
	local EffectiveIntensity = math.max(0, Intensity or DEFAULT_INTENSITY)
	local EffectiveDuration = math.max(0, Duration or DEFAULT_DURATION)
	if EffectiveIntensity <= 0 or EffectiveDuration <= 0 then
		return
	end

	ActiveShakeToken += 1
	local ShakeToken = ActiveShakeToken
	CurrentOffset = CFrame.new()

	task.spawn(function()
		local StartTime = os.clock()
		while true do
			if ShakeToken ~= ActiveShakeToken then
				CurrentOffset = CFrame.new()
				break
			end

			local Elapsed = os.clock() - StartTime
			if Elapsed >= EffectiveDuration then
				break
			end

			local Alpha = 1 - (Elapsed / EffectiveDuration)
			local CurrentIntensity = EffectiveIntensity * Alpha

			local PositionOffset = Vector3.new(
				(math.random() - 0.5) * 2 * CurrentIntensity,
				(math.random() - 0.5) * 2 * CurrentIntensity,
				(math.random() - 0.5) * CurrentIntensity
			)

			local RotationOffset = Vector3.new(
				(math.random() - 0.5) * CurrentIntensity * 2.2,
				(math.random() - 0.5) * CurrentIntensity * 2.2,
				(math.random() - 0.5) * CurrentIntensity * 1.2
			)

			CurrentOffset = CFrame.new(PositionOffset)
				* CFrame.Angles(
					math.rad(RotationOffset.X),
					math.rad(RotationOffset.Y),
					math.rad(RotationOffset.Z)
				)

			RunService.RenderStepped:Wait()
		end

		if ShakeToken == ActiveShakeToken then
			CurrentOffset = CFrame.new()
		end
	end)
end

return CameraShake