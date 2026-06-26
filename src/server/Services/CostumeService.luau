--[[
	CostumeService (service)
	------------------------
	Paints each player's character in their chosen class palette (BodyColors) so the
	8 classes read at a glance — survivors in cool blues, infected in pink / toxic green
	(the 6-15 readability rule). Colors come from ClassConfig.classes[id].Colors and are
	(re)applied by InfectionService on round start, on conversion, and on respawn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local ClassConfig = require(Config:WaitForChild("ClassConfig"))

local CostumeService = {}

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

function CostumeService:Initialize(services)
	self.classes = services.ClassService
end

-- Paint the player's current character in their class palette for `role` (nil = hub, skipped).
function CostumeService:Apply(player: Player, role: string?)
	if not role then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local def = ClassConfig.classes[self.classes:GetClassForRole(player, role)]
	local colors = def and def.Colors
	if not colors then
		return
	end

	local bc = char:FindFirstChildOfClass("BodyColors")
	if not bc then
		bc = Instance.new("BodyColors")
		bc.Parent = char
	end

	if colors.Head then
		bc.HeadColor3 = hex(colors.Head)
	end
	local torso = colors.Torso or colors.Head
	if torso then
		bc.TorsoColor3 = hex(torso)
	end
	local arms = colors.Arms or colors.Torso
	if arms then
		bc.LeftArmColor3 = hex(arms)
		bc.RightArmColor3 = hex(arms)
	end
	local legs = colors.Legs or colors.Torso
	if legs then
		bc.LeftLegColor3 = hex(legs)
		bc.RightLegColor3 = hex(legs)
	end
end

return CostumeService
