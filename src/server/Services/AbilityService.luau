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
	-- Spawned world structures (Engineer barricades, Controller nests) that need
	-- cleanup on owner-leave + round-end so CanCollide parts never block a fresh match.
	self.structures = {} :: { { part: BasePart, kind: string, owner: Player } }
end

function AbilityService:Start()
	self.net.UseAbility.OnServerEvent:Connect(function(player, direction)
		self:_activate(player, direction)
	end)
end

function AbilityService:OnPlayerRemoving(player: Player)
	self.lastUse[player] = nil
	self.cloakToken[player] = nil
	for i = #self.structures, 1, -1 do
		if self.structures[i].owner == player then
			local entry = table.remove(self.structures, i)
			self:_destroyStructure(entry) -- drops the part AND its infection zone (no phantom nest)
		end
	end
end

-- Track a spawned structure and auto-dissolve it after `lifetime` seconds. The caller
-- may set entry.zone afterwards (the matching InfectionService zone) so removal drops both.
function AbilityService:_trackStructure(part: BasePart, kind: string, owner: Player, lifetime: number)
	local entry = { part = part, kind = kind, owner = owner, zone = nil }
	table.insert(self.structures, entry)
	task.delay(lifetime, function()
		self:_removeStructure(entry)
	end)
	return entry
end

-- Destroy a structure's part + its infection zone (does NOT touch self.structures).
function AbilityService:_destroyStructure(entry)
	if not entry then
		return
	end
	if entry.zone then
		self.infection:RemoveZone(entry.zone) -- zone must never outlive its part
	end
	if entry.part.Parent then
		entry.part:Destroy()
	end
end

function AbilityService:_removeStructure(entry)
	local idx = table.find(self.structures, entry)
	if idx then
		table.remove(self.structures, idx)
	end
	self:_destroyStructure(entry)
end

-- Survivor weapon fire damages enemy structures (Controller nests). CombatService calls
-- this on a raycast/melee hit against a part tagged StructureKind=="Nest". At <=0 the nest
-- is removed (part + zone), giving survivors real counterplay against zoning.
function AbilityService:DamageStructure(part: BasePart, amount: number, attacker: Player?)
	for _, entry in self.structures do
		if entry.part == part then
			local hp = (part:GetAttribute("Health") or 0) - amount
			if hp <= 0 then
				self:_removeStructure(entry)
				if attacker and attacker.Parent then
					self.net.CombatFeedback:FireClient(attacker, "hit")
				end
			else
				part:SetAttribute("Health", hp)
				if attacker and attacker.Parent then
					self.net.CombatFeedback:FireClient(attacker, "hit")
				end
			end
			return
		end
	end
end

-- Destroy every spawned structure (round-end). InfectionService:ClearZones() also clears
-- the nest/goo infection zones in the same EndRound pass (belt-and-suspenders w/ RemoveZone).
function AbilityService:ClearStructures()
	for _, entry in self.structures do
		if entry.part.Parent then
			entry.part:Destroy()
		end
	end
	self.structures = {}
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
	elseif abilityId == "Barricade" then
		self:_barricade(player, def, direction)
	elseif abilityId == "MotionPing" then
		self:_motionPing(player, def)
	elseif abilityId == "GroundSlam" then
		self:_groundSlam(player, def)
	elseif abilityId == "CloakLunge" then
		self:_cloakLunge(player, def)
	elseif abilityId == "GooSpit" then
		self:_gooSpit(player, def, direction)
	elseif abilityId == "MutationNest" then
		self:_mutationNest(player, def)
	end
end

-- Horizontal aim from a client-supplied direction, falling back to facing.
local function aimDir(hrp: BasePart, direction): Vector3
	local dir = (typeof(direction) == "Vector3" and direction.Magnitude > 0.01) and direction.Unit
		or hrp.CFrame.LookVector
	dir = Vector3.new(dir.X, 0, dir.Z)
	return dir.Magnitude > 0.01 and dir.Unit or hrp.CFrame.LookVector
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
					self.combat:Stun(target, def.stunDuration)
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
	-- Shatters Engineer barricades caught in the slam (def.breaksBarricade).
	if def.breaksBarricade then
		for i = #self.structures, 1, -1 do
			local entry = self.structures[i]
			if entry.kind == "Barricade" and (entry.part.Position - hrp.Position).Magnitude <= def.radius then
				self:_removeStructure(entry)
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

-- Engineer: drop a destructible wall to seal a lane / shield a downed ally.
function AbilityService:_barricade(player: Player, def, direction)
	local hrp = getRoot(player)
	if not hrp then
		return
	end
	local dir = aimDir(hrp, direction)
	local size = Vector3.new(def.wallSize[1], def.wallSize[2], def.wallSize[3])
	local center = hrp.Position + dir * def.offset
	center = Vector3.new(center.X, hrp.Position.Y - 2.5 + size.Y / 2, center.Z)

	local wall = Instance.new("Part")
	wall.Size = size
	wall.CFrame = CFrame.lookAt(center, center + dir) -- thin axis faces along the lane
	wall.Anchored = true
	wall.CanCollide = true
	wall.Material = Enum.Material.Metal
	wall.Color = Brand.Color.HumanBlue
	wall.Transparency = 0.1
	wall:SetAttribute("Structure", true) -- a Bruiser Ground Slam (breaksBarricade) shatters it; weapons don't (friendly)
	wall:SetAttribute("StructureKind", "Barricade")
	wall:SetAttribute("Health", def.wallHealth)
	wall:SetAttribute("MaxHealth", def.wallHealth)
	wall.Parent = Workspace

	self:_trackStructure(wall, "Barricade", player, def.lifetime)
	burst(center, Brand.Color.HumanBlue, 4)
end

-- Scout: sonar pulse — outline infected within range for the whole survivor team.
function AbilityService:_motionPing(player: Player, def)
	local hrp = getRoot(player)
	if not hrp then
		return
	end
	burst(hrp.Position, Brand.Color.HumanBlue, 6)

	local revealed = {}
	for _, target in Players:GetPlayers() do
		if self.infection:GetRole(target) == GameConfig.ROLE_INFECTED then
			local thrp = getRoot(target)
			if thrp and (thrp.Position - hrp.Position).Magnitude <= def.range then
				table.insert(revealed, target)
			end
		end
	end

	-- Push the outline to every survivor (team-wide intel), including the Scout.
	for _, ally in Players:GetPlayers() do
		if self.infection:GetRole(ally) == GameConfig.ROLE_SURVIVOR then
			self.net.RevealInfected:FireClient(ally, revealed, def.revealDuration)
		end
	end
	self.net.Notify:FireClient(player, "Motion ping: " .. #revealed .. " contact(s)")
end

-- Spitter: lob goo that lands as an infecting pool (registered with InfectionService).
function AbilityService:_gooSpit(player: Player, def, direction)
	local hrp = getRoot(player)
	if not hrp then
		return
	end
	local dir = aimDir(hrp, direction)

	local glob = Instance.new("Part")
	glob.Shape = Enum.PartType.Ball
	glob.Size = Vector3.new(1.6, 1.6, 1.6)
	glob.Color = Brand.Color.HazardYellow
	glob.Material = Enum.Material.Neon
	glob.CanCollide = false
	glob.Position = hrp.Position + dir * 3 + Vector3.new(0, 2, 0)
	glob.AssemblyLinearVelocity = dir * def.throwSpeed + Vector3.new(0, 18, 0)
	glob.Parent = Workspace
	Debris:AddItem(glob, def.fuse + 1)

	task.delay(def.fuse, function()
		local center = glob.Parent and glob.Position or (hrp.Position + dir * def.range)
		glob:Destroy()
		-- Round may have ended during the fuse — RegisterGooPool returns nil then; bail so we
		-- don't spawn an orphan visual that lingers into the next match.
		local zone = self.infection:RegisterGooPool(center, def.poolRadius, def.poolLifetime)
		if not zone then
			return
		end

		-- Flat translucent pool visual (decorative; the infection is the registered zone).
		local pool = Instance.new("Part")
		pool.Shape = Enum.PartType.Cylinder
		pool.Size = Vector3.new(0.6, def.poolRadius * 2, def.poolRadius * 2)
		pool.CFrame = CFrame.new(Vector3.new(center.X, center.Y - 2.4, center.Z)) * CFrame.Angles(0, 0, math.rad(90))
		pool.Anchored = true
		pool.CanCollide = false
		pool.CanQuery = false
		pool.Material = Enum.Material.Neon
		pool.Color = Brand.Color.HazardYellow
		pool.Transparency = 0.55
		pool.Parent = Workspace
		-- Track so ClearStructures() removes it on round-end (keeps part/zone cleanup symmetric).
		local entry = self:_trackStructure(pool, "GooPool", player, def.poolLifetime)
		entry.zone = zone
	end)
end

-- Controller: plant a nest that slows survivors + speeds infection (registered zone).
function AbilityService:_mutationNest(player: Player, def)
	local hrp = getRoot(player)
	if not hrp then
		return
	end
	local center = hrp.Position - Vector3.new(0, 1.5, 0)

	local nest = Instance.new("Part")
	nest.Shape = Enum.PartType.Ball
	nest.Size = Vector3.new(5, 5, 5)
	nest.CFrame = CFrame.new(center)
	nest.Anchored = true
	nest.CanCollide = false
	nest.Material = Enum.Material.Neon
	nest.Color = Brand.Color.InfectedPink
	nest.Transparency = 0.25
	nest:SetAttribute("Structure", true)
	nest:SetAttribute("StructureKind", "Nest")
	nest:SetAttribute("Health", def.nestHealth)
	nest:SetAttribute("MaxHealth", def.nestHealth)
	nest.Parent = Workspace

	local entry = self:_trackStructure(nest, "Nest", player, def.lifetime)
	entry.zone = self.infection:RegisterNest(center, def.nestRadius, player, def.lifetime)
	burst(center, Brand.Color.InfectedPink, def.nestRadius)
end

return AbilityService
