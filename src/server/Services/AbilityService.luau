--[[
	AbilityService (service) — Phase 4
	----------------------------------
	Server-authoritative class signature abilities + cooldowns. One ability per
	class (AbilityConfig.byClass). The client AbilityBarController sends UseAbility
	with an aim direction; the server validates role / class / cooldown / state and
	runs the effect. Cooldown UI is predicted client-side from AbilityConfig.

	Reuses InfectionService (meter add/reduce, movement) and CombatService (stun)
	rather than duplicating logic. (Registered in Main + wired to the UseAbility
	remote during the shared-file pass — dormant until then.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local AbilityService = {}

local STUN_DAMAGE = 1e9 -- enough to drop any infected straight to a stun

local function getRoot(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

-- A short neon "pop" of light at a point — cheap ability juice (server-spawned,
-- replicates to everyone, auto-cleaned by Debris).
local function burst(position: Vector3, color: Color3, maxRadius: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.15
	p.Size = Vector3.new(2, 2, 2)
	p.CFrame = CFrame.new(position)
	p.Parent = Workspace
	TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(maxRadius, maxRadius, maxRadius) * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, 0.6)
end

function AbilityService:Initialize(services)
	self.infection = services.InfectionService
	self.combat = services.CombatService
	self.classes = services.ClassService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self.lastUse = {} :: { [Player]: { [string]: number } }
	self.cloakToken = {} :: { [Player]: number }
end

function AbilityService:Start()
	self.net.UseAbility.OnServerEvent:Connect(function(player, direction)
		self:_activate(player, direction)
	end)
end

function AbilityService:OnPlayerRemoving(player: Player)
	self.lastUse[player] = nil
	self.cloakToken[player] = nil
end

function AbilityService:_activate(player: Player, direction)
	local role = self.infection:GetRole(player)
	if not role or self.infection:IsDowned(player) then
		return
	end
	if role == GameConfig.ROLE_INFECTED and self.combat:IsStunned(player) then
		return
	end
	local abilityId = AbilityConfig.byClass[self.classes:GetClassForRole(player, role)]
	if not abilityId then
		return
	end
	local def = AbilityConfig.abilities[abilityId]

	local now = os.clock()
	self.lastUse[player] = self.lastUse[player] or {}
	-- keyed per ability so a role/class change starts the new ability uncooled
	if (self.lastUse[player][abilityId] or -math.huge) + def.cooldown > now then
		return -- on cooldown
	end
	self.lastUse[player][abilityId] = now

	if abilityId == "FragGrenade" then
		self:_fragGrenade(player, def, direction)
	elseif abilityId == "CleanseBeam" then
		self:_cleanseBeam(player, def)
	elseif abilityId == "GroundSlam" then
		self:_groundSlam(player, def)
	elseif abilityId == "CloakLunge" then
		self:_cloakLunge(player, def)
	end
end

-- Assault: lob a grenade that stuns infected in the blast.
function AbilityService:_fragGrenade(player: Player, def, direction)
	local hrp = getRoot(player)
	if not hrp then
		return
	end
	local dir = (typeof(direction) == "Vector3" and direction.Magnitude > 0.01) and direction.Unit
		or hrp.CFrame.LookVector

	local grenade = Instance.new("Part")
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.new(1.2, 1.2, 1.2)
	grenade.Color = Brand.Color.HazardYellow
	grenade.Material = Enum.Material.Neon
	grenade.CanCollide = true
	grenade.Position = hrp.Position + dir * 3 + Vector3.new(0, 2, 0)
	grenade.AssemblyLinearVelocity = dir * def.throwSpeed + Vector3.new(0, 20, 0)
	grenade.Parent = Workspace
	Debris:AddItem(grenade, def.fuse + 1)

	task.delay(def.fuse, function()
		if not grenade.Parent then
			return
		end
		local center = grenade.Position
		local explosion = Instance.new("Explosion")
		explosion.Position = center
		explosion.BlastRadius = def.blastRadius
		explosion.BlastPressure = 0 -- visual + sound only, no physics knockback
		explosion.DestroyJointRadiusPercent = 0
		explosion.Parent = Workspace
		Debris:AddItem(explosion, 1) -- explicit cleanup (don't rely on Roblox's implicit Explosion GC)
		for _, target in Players:GetPlayers() do
			if self.infection:GetRole(target) == GameConfig.ROLE_INFECTED then
				local thrp = getRoot(target)
				if thrp and (thrp.Position - center).Magnitude <= def.blastRadius then
					self.combat:DamageInfected(target, STUN_DAMAGE, player)
				end
			end
		end
		grenade:Destroy()
	end)
end

-- Medic: drain infection from self + nearby allies.
function AbilityService:_cleanseBeam(player: Player, def)
	local hrp = getRoot(player)
	if not hrp then
		return
	end
	burst(hrp.Position, Brand.Color.SafeGreen, def.radius)
	self.infection:ReduceInfection(player, def.cleanseAmount)
	for _, ally in Players:GetPlayers() do
		if ally ~= player and self.infection:GetRole(ally) == GameConfig.ROLE_SURVIVOR then
			local ahrp = getRoot(ally)
			if ahrp and (ahrp.Position - hrp.Position).Magnitude <= def.radius then
				self.infection:ReduceInfection(ally, def.cleanseAmount)
			end
		end
	end
	self.net.Notify:FireClient(player, "Cleanse pulse!")
end

-- Bruiser: burst of infection to nearby survivors.
function AbilityService:_groundSlam(player: Player, def)
	local hrp = getRoot(player)
	if not hrp then
		return
	end
	burst(hrp.Position - Vector3.new(0, 2, 0), Brand.Color.InfectedPink, def.radius)
	for _, target in Players:GetPlayers() do
		if self.infection:GetRole(target) == GameConfig.ROLE_SURVIVOR then
			local thrp = getRoot(target)
			if thrp and (thrp.Position - hrp.Position).Magnitude <= def.radius then
				self.infection:AddInfection(target, def.infectBurst)
			end
		end
	end
end

-- Stalker: brief cloak + speed surge.
function AbilityService:_cloakLunge(player: Player, def)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum) then
		return
	end
	burst(char:GetPivot().Position, Brand.Color.InfectedPink, 4)

	-- Speed via an attribute so any ApplyMovement (stun/recover/respawn) re-applies
	-- it for the cloak's duration rather than dropping it early.
	player:SetAttribute("CloakSpeedBonus", def.speedBonus)
	self.infection:ApplyMovement(player)

	-- Cloak: snapshot each part's transparency, then dim it (restore exactly later).
	local snapshot: { [BasePart]: number } = {}
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			snapshot[part] = part.Transparency
			part.Transparency = def.transparency
		end
	end

	self.cloakToken[player] = (self.cloakToken[player] or 0) + 1
	local token = self.cloakToken[player]
	task.delay(def.duration, function()
		if self.cloakToken[player] ~= token then
			return -- a newer cloak (or cleanup) superseded this one
		end
		for part, original in snapshot do
			if part.Parent then
				part.Transparency = original
			end
		end
		player:SetAttribute("CloakSpeedBonus", nil)
		self.infection:ApplyMovement(player) -- revert to class default speed
	end)
end

return AbilityService
