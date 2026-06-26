--[[
	CombatService (service)
	-----------------------
	Survivor weapons + infected health/stun. Server-authoritative:
	  - Survivors carry a ranged (hitscan) and a melee Tool.
	  - The client sends an aim direction; the SERVER raycasts from the survivor's
	    own root part (so origin can't be spoofed) and validates cooldown + role.
	  - Infected have a "Health" attribute. Emptying it STUNS them: frozen, can't
	    infect (InfectionService skips stunned), highlighted, for STUN_SECONDS, then
	    they recover at full health. Infected are never killed (asymmetry preserved).

	Couples with InfectionService (injected): role/downed checks + movement, plus
	the infection contact loop skips anyone with the "Stunned" attribute.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local CombatService = {}

local function playerFromInstance(inst: Instance?): Player?
	local current = inst
	while current do
		local found = Players:GetPlayerFromCharacter(current)
		if found then
			return found
		end
		current = current.Parent
	end
	return nil
end

local function makeTool(name: string, kind: string, color: Color3): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponKind", kind)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 4)
	handle.Color = color
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Parent = tool

	return tool
end

function CombatService:Initialize(services)
	self.infection = services.InfectionService
	self.classes = services.ClassService
	self.abilities = services.AbilityService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self.lastUse = {} :: { [Player]: { [string]: number } }
	self.stunToken = {} :: { [Player]: number }
	self.highlights = {} :: { [Player]: Highlight }
end

function CombatService:Start()
	self.net.UseWeapon.OnServerEvent:Connect(function(player, kind, direction)
		self:_useWeapon(player, kind, direction)
	end)
end

-- == Loadout =================================================================

function CombatService:RemoveLoadout(player: Player)
	local function clear(container: Instance?)
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("WeaponKind") ~= nil then
				child:Destroy()
			end
		end
	end
	clear(player:FindFirstChildOfClass("Backpack"))
	clear(player.Character)
end

function CombatService:GiveLoadout(player: Player)
	self:RemoveLoadout(player)
	-- On respawn the Backpack may not have replicated yet; wait briefly so a
	-- respawned survivor never ends up weaponless.
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end
	makeTool(CombatConfig.RANGED_NAME, "Ranged", Color3.fromRGB(120, 200, 255)).Parent = backpack
	makeTool(CombatConfig.MELEE_NAME, "Melee", Color3.fromRGB(255, 220, 120)).Parent = backpack
end

-- == Infected health / stun ==================================================

-- Per-class stun-out threshold (Bruiser tanks, Stalker is squishy). Falls back to
-- the flat config value if the class lookup is unavailable.
function CombatService:_maxHealth(player: Player): number
	return self.classes:GetInfectedHealth(player) or CombatConfig.INFECTED_MAX_HEALTH
end

function CombatService:InitInfected(player: Player)
	player:SetAttribute("Health", self:_maxHealth(player))
	player:SetAttribute("Stunned", false)
end

function CombatService:IsStunned(player: Player): boolean
	return player:GetAttribute("Stunned") == true
end

-- Re-applies the stun highlight after a respawn (the old highlight died with the
-- old character, but the Stunned attribute itself survives on the Player).
function CombatService:RefreshStun(player: Player)
	if self:IsStunned(player) then
		self:_setHighlight(player, true)
	end
end

function CombatService:_setHighlight(player: Player, on: boolean)
	local existing = self.highlights[player]
	if existing then
		existing:Destroy()
		self.highlights[player] = nil
	end
	if on and player.Character then
		local hl = Instance.new("Highlight")
		hl.FillColor = Brand.Color.HazardYellow -- stunned = "warning / opportunity"
		hl.OutlineColor = Brand.Color.HazardYellow
		hl.FillTransparency = 0.45
		hl.Parent = player.Character
		self.highlights[player] = hl
	end
end

function CombatService:_recover(player: Player)
	player:SetAttribute("Stunned", false)
	player:SetAttribute("Health", self:_maxHealth(player))
	self:_setHighlight(player, false)
	self.infection:ApplyMovement(player)
end

-- Public stun (FragGrenade, etc. pass an explicit duration). Guards mirror DamageInfected.
function CombatService:Stun(player: Player, duration: number?)
	if self.infection:GetRole(player) ~= GameConfig.ROLE_INFECTED then
		return
	end
	self:_stun(player, duration)
end

function CombatService:_stun(player: Player, duration: number?)
	if self:IsStunned(player) then
		return
	end
	player:SetAttribute("Stunned", true)
	player:SetAttribute("Health", 0)
	self.infection:ApplyMovement(player) -- frozen while stunned
	self:_setHighlight(player, true)
	self.net.Notify:FireClient(player, "Stunned! Recovering...")

	self.stunToken[player] = (self.stunToken[player] or 0) + 1
	local token = self.stunToken[player]
	task.delay(duration or CombatConfig.STUN_SECONDS, function()
		-- Only recover if this stun is still the active one and they're still infected.
		if
			self.stunToken[player] == token
			and player.Parent
			and self.infection:GetRole(player) == GameConfig.ROLE_INFECTED
		then
			self:_recover(player)
		end
	end)
end

function CombatService:DamageInfected(target: Player, amount: number, attacker: Player?, source: string?)
	if self.infection:GetRole(target) ~= GameConfig.ROLE_INFECTED then
		return
	end
	if self:IsStunned(target) then
		return
	end
	local hp = (target:GetAttribute("Health") or self:_maxHealth(target)) - amount
	if hp <= 0 then
		-- Assault passive: their Stun Baton (melee) holds the infected stunned longer.
		local duration = CombatConfig.STUN_SECONDS
		if source == "Melee" and attacker then
			local mult = self.classes:GetPassive(attacker, GameConfig.ROLE_SURVIVOR).BatonStunMult
			if mult then
				duration *= mult
			end
		end
		self:_stun(target, duration)
	else
		target:SetAttribute("Health", hp)
	end
	if attacker and attacker.Parent then
		self.net.CombatFeedback:FireClient(attacker, "hit")
	end
end

-- == Weapon use (validated, server-authoritative) ============================

-- True if nothing solid sits between two points — melee line-of-sight, so the
-- baton can't reach through walls and break the rescue standoff from cover.
function CombatService:_clearPath(fromPos: Vector3, toPos: Vector3, charA: Instance, charB: Instance): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { charA, charB }
	return Workspace:Raycast(fromPos, toPos - fromPos, params) == nil
end

function CombatService:_useWeapon(player: Player, kind, direction)
	if typeof(kind) ~= "string" or (kind ~= "Ranged" and kind ~= "Melee") then
		return -- reject unknown kinds (prevents cooldown-bypass + unbounded lastUse growth)
	end
	if self.infection:GetRole(player) ~= GameConfig.ROLE_SURVIVOR or self.infection:IsDowned(player) then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	-- Must actually have the matching weapon equipped (Activated only fires when equipped).
	local equipped = char:FindFirstChildOfClass("Tool")
	if not equipped or equipped:GetAttribute("WeaponKind") ~= kind then
		return
	end
	if kind == "Ranged" then
		-- Validate aim BEFORE consuming the cooldown slot. Free-aim from the server-known
		-- origin is intended (the body doesn't face the camera); we only reject malformed
		-- vectors — a NaN/inf component makes Magnitude NaN, and a zero/near-zero direction.
		if typeof(direction) ~= "Vector3" then
			return
		end
		local mag = direction.Magnitude
		if mag ~= mag or mag < 0.01 then
			return
		end
	end

	local now = os.clock()
	self.lastUse[player] = self.lastUse[player] or {}
	local cooldown = if kind == "Melee" then CombatConfig.MELEE_COOLDOWN else CombatConfig.RANGED_COOLDOWN
	if (self.lastUse[player][kind] or 0) + cooldown > now then
		return
	end
	self.lastUse[player][kind] = now

	if kind == "Ranged" then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local result = Workspace:Raycast((hrp :: BasePart).Position, direction.Unit * CombatConfig.RANGED_RANGE, params)
		if result then
			local victim = playerFromInstance(result.Instance)
			if victim and victim ~= player then
				self:DamageInfected(victim, CombatConfig.RANGED_DAMAGE, player, "Ranged")
			elseif result.Instance:GetAttribute("StructureKind") == "Nest" then
				-- Survivors can shoot down a Controller nest (counterplay against zoning).
				self.abilities:DamageStructure(result.Instance, CombatConfig.RANGED_DAMAGE, player)
			end
		end
	elseif kind == "Melee" then
		for _, target in Players:GetPlayers() do
			if target ~= player and self.infection:GetRole(target) == GameConfig.ROLE_INFECTED then
				local targetChar = target.Character
				local thrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
				if thrp then
					local from = (hrp :: BasePart).Position
					local to = (thrp :: BasePart).Position
					-- In range AND not behind a wall (line-of-sight, like the ranged ray gets for free).
					if
						(to - from).Magnitude <= CombatConfig.MELEE_RANGE
						and self:_clearPath(from, to, char, targetChar)
					then
						self:DamageInfected(target, CombatConfig.MELEE_DAMAGE, player, "Melee")
					end
				end
			end
		end
	end
end

-- == Cleanup =================================================================

function CombatService:ClearCombat(player: Player)
	self:RemoveLoadout(player)
	self:_setHighlight(player, false)
	self.stunToken[player] = (self.stunToken[player] or 0) + 1 -- cancel any pending recover
	self.lastUse[player] = nil
	player:SetAttribute("Health", nil) -- remove entirely so nothing lingers in the hub
	player:SetAttribute("Stunned", nil)
end

function CombatService:OnPlayerRemoving(player: Player)
	self:_setHighlight(player, false)
	self.lastUse[player] = nil
	self.stunToken[player] = nil
	self.highlights[player] = nil
end

return CombatService
