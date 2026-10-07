repeat task.wait() until game:IsLoaded()

local assets = {}
local ContentProvider = game:GetService('ContentProvider')

local loader = script.PreloadHelper :: Model
local Animator: Animator = loader.Humanoid.Animator

for _, anim in next, game:GetDescendants() do
	if not anim:IsA("Animation") then
		continue
	end
	if anim.AnimationId == "" then
		continue
	end
	
	table.insert(assets, anim)
	Animator:LoadAnimation(anim)
end

ContentProvider:PreloadAsync(assets)

task.wait(5)

loader:Destroy()
script:Destroy()