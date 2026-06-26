--[[
	InfectionService (service)
	--------------------------
	The real infection mechanic. Server-authoritative,
	roster-scoped.

	- Survivors carry an INFECTION meter (0-100), replicated via the "Infection" attribute.
	- Standing within CONTACT_RANGE of an infected fills it; breaking contact lets it decay.
	- At 100% a survivor is DOWNED ("Downed" attribute = true, can't move) and a bleed-out
	  timer starts.
	- A standing survivor holds a rescue ProximityPrompt to revive them — UNLESS an infected
	  is guarding within SECURE_RANGE, which disables the prompt (the standoff).
	- If the bleed-out timer expires, the downed survivor converts to infected.

	A single server loop (every TICK seconds) drives contact, decay, downing, the rescue-
	prompt gating, and bleed-out, so no per-character touch hooks are needed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local RoundConfig = require(Config:WaitForChild("RoundConfig"))
local InfectionConfig = require(Config:WaitForChild("InfectionConfig"))
local ClassConfig = require(Config:WaitForChild("ClassConfig"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local InfectionService = {}

local rng = Random.new()

local function disconnectAll(list: { RBXScriptConnection })
	for _, c in list do
		c:Disconnect()
	end
end

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function getRootPart(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

function InfectionService:Initialize(services)
	self.teams = services.TeamManager
	self.economy = services.EconomyService
	self.combat = services.CombatService
	self.classes = services.ClassService
	self.costume = services.CostumeService
	self.map = services.MapService
	self.stats = services.StatsService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))

	self.roles = {} :: { [Player]: string? }
	self.isPatientZero = {} :: { [Player]: boolean }
	self.pzBuffed = {} :: { [Player]: boolean } -- PZ early-buff active (speed/health/range); expires after BuffDuration
	self.infection = {} :: { [Player]: number } -- 0-100, survivors only
	self.downed = {} :: { [Player]: boolean }
	self.downedSince = {} :: { [Player]: number }
	self.immuneUntil = {} :: { [Player]: number }
	self.lastContact = {} :: { [Player]: number }
	self.rescuePrompts = {} :: { [Player]: ProximityPrompt }
	self.playerConns = {} :: { [Player]: { RBXScriptConnection } }
	self.roundActive = false
	self.conversions = 0
	-- Ability zones (Phase 4): Spitter goo pools + Controller nests fill/slow survivors.
	self.gooPools = {} :: { { center: Vector3, radius: number, expires: number } }
	self.nests = {} :: { { center: Vector3, radius: number, owner: Player, expires: number } }
	self.inNest = {} :: { [Player]: boolean } -- survivors currently inside a nest (drives the slow)
	self.inSlow = {} :: { [Player]: boolean } -- survivors currently in a Slow hazard zone (flooded room)
end

-- == Helpers =================================================================

function InfectionService:_setInfection(player: Player, value: number)
	value = math.clamp(value, 0, 100)
	self.infection[player] = value
	player:SetAttribute("Infection", value)
end

function InfectionService:_applyMovement(player: Player)
	local hum = getHumanoid(player)
	if not hum then
		return
	end
	hum.UseJumpPower = true
	hum.JumpPower = GameConfig.JUMP_POWER

	if self.downed[player] then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		return
	end
	local role = self.roles[player]
	if role == GameConfig.ROLE_INFECTED and player:GetAttribute("Stunned") then
		hum.WalkSpeed = 0 -- frozen while stunned by weapons fire
		hum.JumpPower = 0
		return
	end
	if role then
		-- per-class speed (Phase 4) + any active cloak surge (re-applied on stun/respawn)
		local base = self.classes:GetWalkSpeed(player, role)
		if role == GameConfig.ROLE_INFECTED and self.pzBuffed[player] then
			base = ClassConfig.PatientZero.WalkSpeed -- buffed Patient Zero outpaces its base class
		end
		local speed = base + (player:GetAttribute("CloakSpeedBonus") or 0)
		if role == GameConfig.ROLE_SURVIVOR and self.inNest[player] then
			speed *= InfectionConfig.NEST_SLOW_MULT -- inside a Controller nest
		end
		if role == GameConfig.ROLE_SURVIVOR and self.map then
			local shrp = getRootPart(player)
			if shrp then
				speed *= self.map:HazardSlowMult(shrp.Position) -- flooded-room slow hazard
			end
		end
		hum.WalkSpeed = speed
	else
		hum.WalkSpeed = GameConfig.SURVIVOR_WALKSPEED -- hub default
	end
end

function InfectionService:_isImmune(player: Player): boolean
	local expiry = self.immuneUntil[player]
	return expiry ~= nil and os.clock() < expiry
end

function InfectionService:_infectedPositions(): { Vector3 }
	local positions = {}
	for player, role in self.roles do
		-- Stunned infected neither infect nor block a rescue (shoot the guard to free an ally).
		if role == GameConfig.ROLE_INFECTED and not player:GetAttribute("Stunned") then
			local hrp = getRootPart(player)
			if hrp then
				table.insert(positions, hrp.Position)
			end
		end
	end
	return positions
end

-- Like _infectedPositions but tags each with its contact range (buffed PZ reaches further).
function InfectionService:_infectedContacts(): { { pos: Vector3, range: number } }
	local out = {}
	for player, role in self.roles do
		if role == GameConfig.ROLE_INFECTED and not player:GetAttribute("Stunned") then
			local hrp = getRootPart(player)
			if hrp then
				local range = InfectionConfig.CONTACT_RANGE
				if self.pzBuffed[player] then
					range *= ClassConfig.PatientZero.InfectRangeMult
				end
				table.insert(out, { pos = hrp.Position, range = range })
			end
		end
	end
	return out
end

local function anyWithin(positions: { Vector3 }, target: Vector3, range: number): boolean
	for _, pos in positions do
		if (pos - target).Magnitude <= range then
			return true
		end
	end
	return false
end

-- Horizontal membership test against a list of {center, radius} ability zones.
local function inZone(zones: { any }, pos: Vector3): boolean
	for _, z in zones do
		if Vector3.new(pos.X - z.center.X, 0, pos.Z - z.center.Z).Magnitude <= z.radius then
			return true
		end
	end
	return false
end

-- Per-infected contact test (each infected carries its OWN range, so a buffed
-- Patient Zero can reach further). Rescue/prompt SECURE_RANGE still uses the plain
-- position list — only contact-fill needs per-infected range.
local function anyContact(contacts: { { pos: Vector3, range: number } }, target: Vector3): boolean
	for _, c in contacts do
		if (c.pos - target).Magnitude <= c.range then
			return true
		end
	end
	return false
end

function InfectionService:_removePrompt(player: Player)
	local prompt = self.rescuePrompts[player]
	if prompt then
		prompt:Destroy()
		self.rescuePrompts[player] = nil
	end
	-- Remove the world-space downed beacon (created alongside the prompt).
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local beacon = hrp and hrp:FindFirstChild("DownedBeacon")
	if beacon then
		beacon:Destroy()
	end
end

-- Creates the rescue prompt on a downed player's HRP if it's missing (and the
-- HRP exists). Safe to call every tick — it no-ops once a prompt is present, so
-- a player downed mid-respawn (no HRP yet) still gets a prompt the next tick.
function InfectionService:_ensurePrompt(player: Player)
	if self.rescuePrompts[player] then
		return
	end
	local hrp = getRootPart(player)
	if not hrp then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RescuePrompt"
	prompt.ActionText = "Rescue"
	prompt.ObjectText = player.Name
	prompt.HoldDuration = InfectionConfig.RESCUE_SECONDS
	prompt.MaxActivationDistance = InfectionConfig.RESCUE_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = hrp
	prompt.Triggered:Connect(function(rescuer)
		self:_tryRescue(player, rescuer)
	end)
	self.rescuePrompts[player] = prompt

	-- Big world-space beacon so allies can spot (and run to) a downed teammate
	-- through walls. Green = "help / rescue me" (the 7-year-old readability rule).
	if not hrp:FindFirstChild("DownedBeacon") then
		local beacon = Instance.new("BillboardGui")
		beacon.Name = "DownedBeacon"
		beacon.Size = UDim2.fromOffset(150, 52)
		beacon.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
		beacon.AlwaysOnTop = true
		beacon.MaxDistance = 250
		beacon.Parent = hrp
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Brand.Font.Display
		label.TextScaled = true
		label.TextColor3 = Brand.Color.SafeGreen
		label.TextStrokeTransparency = 0.25
		label.Text = "RESCUE"
		label.Parent = beacon
	end
end

-- == Downed / rescue / convert ===============================================

function InfectionService:_down(player: Player)
	if self.downed[player] then
		return
	end
	self.downed[player] = true
	self.downedSince[player] = os.clock()
	self:_setInfection(player, 100)
	player:SetAttribute("Downed", true)
	self:_applyMovement(player) -- immobilize
	self:_ensurePrompt(player)

	self.net.Notify:FireClient(player, "You're DOWN! Hold on for a rescue...")
	for other, role in self.roles do
		if other ~= player and role == GameConfig.ROLE_SURVIVOR and other.Parent then
			self.net.Notify:FireClient(other, player.Name .. " is down — go rescue them!")
		end
	end
end

function InfectionService:_tryRescue(downedPlayer: Player, rescuer: Player)
	if not self.downed[downedPlayer] then
		return
	end
	if self.roles[rescuer] ~= GameConfig.ROLE_SURVIVOR or self.downed[rescuer] then
		return
	end
	local hrp = getRootPart(downedPlayer)
	if hrp and anyWithin(self:_infectedPositions(), hrp.Position, InfectionConfig.SECURE_RANGE) then
		self.net.Notify:FireClient(rescuer, "Can't rescue — infected too close!")
		return
	end

	self.downed[downedPlayer] = nil
	self.downedSince[downedPlayer] = nil
	self.lastContact[downedPlayer] = nil
	downedPlayer:SetAttribute("Downed", false)
	self:_removePrompt(downedPlayer)
	self:_setInfection(downedPlayer, InfectionConfig.RESCUE_INFECTION)
	self.immuneUntil[downedPlayer] = os.clock() + InfectionConfig.SPAWN_IMMUNITY
	self:_applyMovement(downedPlayer)

	self.net.Notify:FireClient(downedPlayer, "Rescued! Get moving!")
	self.net.KillFeed:FireAllClients("rescue", rescuer.Name, downedPlayer.Name)
	if rescuer.Parent then
		self.economy:AddCoins(rescuer, GameConfig.REWARD_RESCUE)
		self.net.Notify:FireClient(rescuer, "You rescued " .. downedPlayer.Name .. "!  +" .. GameConfig.REWARD_RESCUE)
		self.stats:Add(rescuer, "rescues", 1)
	end
end

function InfectionService:_convert(player: Player)
	if self.roles[player] ~= GameConfig.ROLE_SURVIVOR then
		return
	end
	self.roles[player] = GameConfig.ROLE_INFECTED
	self.conversions += 1
	-- Tell the client its new role BEFORE zeroing the meter attributes, so the
	-- HUD drops the survivor meter without a one-frame empty-bar flicker.
	self.net.RoleAssigned:FireClient(player, GameConfig.ROLE_INFECTED)

	self.downed[player] = nil
	self.downedSince[player] = nil
	self.infection[player] = nil
	self.isPatientZero[player] = false
	self.immuneUntil[player] = nil
	self.lastContact[player] = nil
	self.inNest[player] = nil
	self.inSlow[player] = nil
	player:SetAttribute("Downed", false)
	player:SetAttribute("Infection", 0)
	self:_removePrompt(player)
	self.teams:ToInfected(player)
	self.combat:RemoveLoadout(player)
	self.combat:InitInfected(player)
	self:_applyMovement(player)
	self.costume:Apply(player, GameConfig.ROLE_INFECTED)

	self.net.Notify:FireClient(player, "You've turned! Hunt the survivors.")
	self.net.KillFeed:FireAllClients("infect", player.Name)
end

-- == The driving loop ========================================================

function InfectionService:_tick(dt: number)
	local now = os.clock()
	self:_pruneZones(now) -- drop expired goo pools / nests
	-- Safe to iterate: _convert only rewrites an existing self.roles VALUE; nothing
	-- here may ADD or REMOVE self.roles keys during the loop.
	local infectedPos = self:_infectedPositions() -- plain list: rescue / prompt SECURE_RANGE
	local contacts = self:_infectedContacts() -- per-infected range: contact-fill (buffed PZ reaches further)

	-- Medic passive (AllyDecayMult): standing survivors near a Medic decay faster.
	local medics = {}
	for player, role in self.roles do
		if role == GameConfig.ROLE_SURVIVOR and not self.downed[player] then
			local mult = self.classes:GetPassive(player, GameConfig.ROLE_SURVIVOR).AllyDecayMult
			if mult then
				local mhrp = getRootPart(player)
				if mhrp then
					table.insert(medics, { pos = mhrp.Position, mult = mult })
				end
			end
		end
	end

	for player, role in self.roles do
		if role ~= GameConfig.ROLE_SURVIVOR then
			continue
		end

		if self.downed[player] then
			-- Bleed out -> convert, otherwise keep a rescue prompt alive and gate
			-- it on whether an infected is guarding the body.
			local since = self.downedSince[player]
			if since and now - since >= InfectionConfig.BLEED_OUT_SECONDS then
				self:_convert(player)
			else
				self:_ensurePrompt(player) -- (re)create if it was missing or lost on respawn
				local prompt = self.rescuePrompts[player]
				local hrp = getRootPart(player)
				if prompt and hrp then
					prompt.Enabled = not anyWithin(infectedPos, hrp.Position, InfectionConfig.SECURE_RANGE)
				end
			end
		else
			local hrp = getRootPart(player)
			if hrp then
				-- Controller nest slow: re-apply movement only when nest membership flips.
				local nowInNest = inZone(self.nests, hrp.Position)
				if nowInNest ~= (self.inNest[player] == true) then
					self.inNest[player] = nowInNest
					self:_applyMovement(player)
				end

				-- Flooded-room slow: re-apply movement only when slow-zone membership flips.
				local nowSlow = self.map ~= nil and self.map:HazardSlowMult(hrp.Position) < 1
				if nowSlow ~= (self.inSlow[player] == true) then
					self.inSlow[player] = nowSlow
					self:_applyMovement(player)
				end

				local immune = self:_isImmune(player)
				local current = self.infection[player] or 0
				local contact = anyContact(contacts, hrp.Position)
				local hazardFill = if self.map ~= nil then self.map:HazardFillRate(hrp.Position) else 0
				local goo = inZone(self.gooPools, hrp.Position)
				if contact or hazardFill > 0 or goo or nowInNest then
					self.lastContact[player] = now
					if not immune then
						-- contact and/or hazard both fill; immunity blocks GAIN, not decay
						local rate = (contact and InfectionConfig.FILL_RATE or 0)
							+ hazardFill
							+ (goo and InfectionConfig.GOO_POOL_FILL_RATE or 0)
							+ (nowInNest and InfectionConfig.NEST_FILL_BONUS or 0)
						current += rate * self.classes:GetFillMult(player) * dt
					end
				elseif now - (self.lastContact[player] or 0) >= InfectionConfig.DECAY_DELAY then
					local decayMult = 1
					for _, m in medics do
						if (m.pos - hrp.Position).Magnitude <= InfectionConfig.MEDIC_AURA_RANGE then
							decayMult = math.max(decayMult, m.mult)
						end
					end
					current -= InfectionConfig.DECAY_RATE * decayMult * dt
				end
				self:_setInfection(player, current)
				if not immune and (self.infection[player] or 0) >= 100 then
					self:_down(player)
				end
			end
		end
	end

	-- Phase 5: drive the objective race off this same loop, reusing the infected
	-- positions we already computed. nil-guarded so infection still runs standalone.
	if self.objectives then
		self.objectives:Tick(dt, infectedPos)
	end
end

function InfectionService:_startLoop()
	-- Generation token: a second StartRound (re-entrancy) supersedes this loop
	-- instead of running two concurrent loops that double-tick the meter.
	self._loopGen = (self._loopGen or 0) + 1
	local gen = self._loopGen
	task.spawn(function()
		local last = os.clock()
		while self.roundActive and self._loopGen == gen do
			task.wait(InfectionConfig.TICK)
			local now = os.clock()
			self:_tick(now - last) -- real elapsed time, not nominal, so rates hold under load
			last = now
		end
	end)
end

-- == Public API (called by RoundService / Main) ==============================

function InfectionService:OnPlayerAdded(player: Player)
	self.playerConns[player] = {}
	self.roles[player] = nil
	self.isPatientZero[player] = false
	self.pzBuffed[player] = false
	player:SetAttribute("Infection", 0)
	player:SetAttribute("Downed", false)

	local conn = player.CharacterAdded:Connect(function()
		self:_onCharacterAdded(player)
	end)
	table.insert(self.playerConns[player], conn)
end

function InfectionService:_onCharacterAdded(player: Player)
	local char = player.Character
	if not char then
		return
	end
	char:WaitForChild("Humanoid", 5)
	char:WaitForChild("HumanoidRootPart", 5)

	local wasDowned = self.downed[player] == true
	-- Clear downed state off the old body onto the fresh one.
	if wasDowned then
		self.downed[player] = nil
		self.downedSince[player] = nil
		self:_removePrompt(player)
		player:SetAttribute("Downed", false)
	end

	if self.roundActive and self.roles[player] == GameConfig.ROLE_SURVIVOR then
		if wasDowned then
			-- Reset-to-escape guard: a survivor who respawns while DOWNED mid-round (e.g.
			-- hit Roblox's Reset Character to dodge bleed-out) is CONVERTED, not handed a
			-- fresh clean body + immunity. Resetting while down = you went down.
			self:_convert(player)
			return
		end
		-- Benign respawn (was not downed): start clean so a stale ~100 meter can't re-down them.
		self:_setInfection(player, 0)
		self.lastContact[player] = nil
		self.immuneUntil[player] = os.clock() + InfectionConfig.SPAWN_IMMUNITY
		self.inNest[player] = nil -- fresh body isn't in a nest; clear so it doesn't inherit the slow
		self.inSlow[player] = nil
		self.combat:GiveLoadout(player) -- re-issue weapons on a fresh body
	elseif self.roundActive and self.roles[player] == GameConfig.ROLE_INFECTED then
		-- Stunned survives respawn (drives the freeze + pending recover); re-create
		-- the stun highlight that died with the old character.
		self.combat:RefreshStun(player)
	end
	self:_applyMovement(player)
	self.costume:Apply(player, self.roles[player]) -- repaint class palette on the fresh body
end

function InfectionService:OnPlayerRemoving(player: Player)
	self:_removePrompt(player)
	if self.playerConns[player] then
		disconnectAll(self.playerConns[player])
	end
	self.playerConns[player] = nil
	self.roles[player] = nil
	self.isPatientZero[player] = nil
	self.pzBuffed[player] = nil
	self.infection[player] = nil
	self.downed[player] = nil
	self.downedSince[player] = nil
	self.immuneUntil[player] = nil
	self.lastContact[player] = nil
	self.inNest[player] = nil
	self.inSlow[player] = nil
end

function InfectionService:StartRound(roster: { Player })
	self.conversions = 0

	-- At least 1 infected, but always leave at least 1 survivor — so a small roster
	-- can't become all-infected at the whistle, and rescue stays possible.
	local zeroCount = math.clamp(math.floor(#roster / RoundConfig.PATIENT_ZERO_RATIO), 1, math.max(1, #roster - 1))
	local pool = table.clone(roster)
	local chosen: { [Player]: boolean } = {}
	for _ = 1, math.min(zeroCount, #pool) do
		local index = rng:NextInteger(1, #pool)
		chosen[pool[index]] = true
		table.remove(pool, index)
	end

	self.roundActive = true
	self._pzGen = (self._pzGen or 0) + 1 -- invalidates any prior round's pending PZ-normalize closures

	for _, player in roster do
		self.isPatientZero[player] = chosen[player] == true
		self.pzBuffed[player] = chosen[player] == true -- buff active; _applyMovement reads it for PZ speed
		self.downed[player] = nil
		self.downedSince[player] = nil
		self.lastContact[player] = nil
		player:SetAttribute("Downed", false)

		if chosen[player] then
			self.roles[player] = GameConfig.ROLE_INFECTED
			self.infection[player] = nil
			player:SetAttribute("Infection", 0)
			self.teams:ToInfected(player)
			self.combat:InitInfected(player)
			-- Buffed stun-out threshold: a FLOOR, never below the class value (a tank PZ like
			-- Bruiser 350 must not be nerfed to 220 during its opener).
			player:SetAttribute(
				"Health",
				math.max(self.classes:GetInfectedHealth(player), ClassConfig.PatientZero.Health)
			)
			self:_schedulePZNormalize(player)
			self.net.RoleAssigned:FireClient(player, GameConfig.ROLE_INFECTED)
			self.net.Notify:FireClient(player, "You are PATIENT ZERO! Infect the survivors.")
		else
			self.roles[player] = GameConfig.ROLE_SURVIVOR
			self:_setInfection(player, 0)
			self.immuneUntil[player] = os.clock() + InfectionConfig.SPAWN_IMMUNITY
			self.teams:ToSurvivor(player)
			self.combat:GiveLoadout(player)
			self.net.RoleAssigned:FireClient(player, GameConfig.ROLE_SURVIVOR)
			self.net.Notify:FireClient(player, "You are a SURVIVOR! Keep your infection below 100%.")
		end
		self:_applyMovement(player)
		self.costume:Apply(player, self.roles[player])
	end

	-- Outbreak Pulse: briefly reveal every survivor to each Patient Zero at spawn.
	local survivors = {}
	for player, role in self.roles do
		if role == GameConfig.ROLE_SURVIVOR then
			table.insert(survivors, player)
		end
	end
	for player in self.pzBuffed do
		if self.pzBuffed[player] and player.Parent then
			self.net.RevealSurvivors:FireClient(player, survivors, ClassConfig.PatientZero.RevealDuration)
		end
	end

	self.net.KillFeed:FireAllClients("outbreak")
	self:_startLoop()
end

-- After BuffDuration the Patient Zero normalizes to its chosen infected class
-- (speed drops, stun-out health clamps down to the class value).
function InfectionService:_schedulePZNormalize(player: Player)
	local gen = self._pzGen
	task.delay(ClassConfig.PatientZero.BuffDuration, function()
		if self._pzGen ~= gen or not self.pzBuffed[player] then
			return -- a new round (or an early un-buff) superseded this schedule
		end
		self.pzBuffed[player] = false
		if self.roles[player] == GameConfig.ROLE_INFECTED then
			self:_applyMovement(player)
			local classMax = self.classes:GetInfectedHealth(player)
			local current = player:GetAttribute("Health") or classMax
			player:SetAttribute("Health", math.min(current, classMax))
		end
	end)
end

function InfectionService:EndRound(roster: { Player })
	self.roundActive = false
	self:ClearZones() -- drop goo pools / nests so CanCollide parts don't block next match
	for _, player in roster do
		self:_removePrompt(player)
		self.combat:ClearCombat(player)
		self.roles[player] = nil
		self.isPatientZero[player] = false
		self.pzBuffed[player] = false
		self.infection[player] = nil
		self.downed[player] = nil
		self.downedSince[player] = nil
		self.immuneUntil[player] = nil
		self.lastContact[player] = nil
		player:SetAttribute("Infection", 0)
		player:SetAttribute("Downed", false)
		self.teams:ToLobby(player)
		self:_applyMovement(player)
	end
end

function InfectionService:GetRole(player: Player): string?
	return self.roles[player]
end

function InfectionService:IsDowned(player: Player): boolean
	return self.downed[player] == true
end

-- Public wrapper so CombatService can re-apply movement after a stun/recover.
function InfectionService:ApplyMovement(player: Player)
	self:_applyMovement(player)
end

-- Ability hooks (Phase 4): adjust a survivor's infection meter. Ability-driven infection
-- (e.g. Bruiser Ground Slam) honors the class fillMult tankiness lever, like passive fill.
function InfectionService:AddInfection(player: Player, amount: number)
	if self.roles[player] ~= GameConfig.ROLE_SURVIVOR or self.downed[player] or self:_isImmune(player) then
		return
	end
	self:_setInfection(player, (self.infection[player] or 0) + amount * self.classes:GetFillMult(player))
	if (self.infection[player] or 0) >= 100 then
		self:_down(player)
	end
end

function InfectionService:ReduceInfection(player: Player, amount: number)
	if self.roles[player] ~= GameConfig.ROLE_SURVIVOR or self.downed[player] then
		return
	end
	self:_setInfection(player, (self.infection[player] or 0) - amount)
end

-- Instantly down a survivor (e.g. a direct hit by the Line 0 train). Respects immunity
-- and the survivor / already-downed guards, like the contact path.
function InfectionService:ForceDown(player: Player)
	if self.roles[player] ~= GameConfig.ROLE_SURVIVOR or self.downed[player] or self:_isImmune(player) then
		return
	end
	self:_setInfection(player, 100)
	self:_down(player)
end

-- == Ability zones (Spitter goo pools / Controller nests) ====================

function InfectionService:_pruneZones(now: number)
	for i = #self.gooPools, 1, -1 do
		if self.gooPools[i].expires <= now then
			table.remove(self.gooPools, i)
		end
	end
	for i = #self.nests, 1, -1 do
		if self.nests[i].expires <= now then
			table.remove(self.nests, i)
		end
	end
end

function InfectionService:IsRoundActive(): boolean
	return self.roundActive == true
end

-- Spitter Goo Spit: an infecting pool (AbilityService spawns the visual part separately).
-- Returns the zone table (or nil if the round already ended) so the caller can drop it later.
function InfectionService:RegisterGooPool(center: Vector3, radius: number, lifetime: number)
	if not self.roundActive then
		return nil -- a delayed fuse landing after EndRound must not leak a zone into the next match
	end
	local zone = { center = center, radius = radius, expires = os.clock() + lifetime }
	table.insert(self.gooPools, zone)
	return zone
end

-- Controller Mutation Nest: a slow + infect zone. Returns the zone table so the owning
-- structure can remove it when the nest is shot down / its owner leaves.
function InfectionService:RegisterNest(center: Vector3, radius: number, owner: Player, lifetime: number)
	if not self.roundActive then
		return nil
	end
	local zone = { center = center, radius = radius, owner = owner, expires = os.clock() + lifetime }
	table.insert(self.nests, zone)
	return zone
end

-- Remove a single zone (by reference) early — e.g. a nest shot down or its owner left.
-- The next tick re-flags inNest for anyone who was standing in it.
function InfectionService:RemoveZone(zone)
	if not zone then
		return
	end
	local i = table.find(self.nests, zone)
	if i then
		table.remove(self.nests, i)
		return
	end
	i = table.find(self.gooPools, zone)
	if i then
		table.remove(self.gooPools, i)
	end
end

function InfectionService:ClearZones()
	self.gooPools = {}
	self.nests = {}
	self.inNest = {}
	self.inSlow = {}
end

-- Phase 5 comeback: a team-wide cleanse fired when a generator is powered. Revives
-- every DOWNED survivor (same as a rescue) and knocks `relief` infection off every
-- standing survivor, granting brief immunity to all. Only rewrites existing self.roles
-- VALUES indirectly — never adds/removes keys — so it's safe vs the _tick iteration.
-- SAFETY INVARIANT: this fires from a ProximityPrompt handler, i.e. BETWEEN ticks — which
-- holds ONLY because _tick and ObjectiveService:Tick are entirely yield-free. Do NOT add
-- task.wait / async calls inside those tick paths, or this becomes a real mid-iteration race.
function InfectionService:CleansePulse(relief: number, immunitySeconds: number)
	for player, role in self.roles do
		if role ~= GameConfig.ROLE_SURVIVOR or not player.Parent then
			continue
		end
		if self.downed[player] then
			-- Back on your feet at the rescue infection level (mirrors _tryRescue).
			self.downed[player] = nil
			self.downedSince[player] = nil
			self.lastContact[player] = nil
			player:SetAttribute("Downed", false)
			self:_removePrompt(player)
			self:_setInfection(player, InfectionConfig.RESCUE_INFECTION)
		else
			self:_setInfection(player, (self.infection[player] or 0) - relief)
		end
		self.immuneUntil[player] = os.clock() + immunitySeconds
		self:_applyMovement(player)
		self.net.Notify:FireClient(player, "\u{2728} CLEANSE! Infection purged!")
	end
end

function InfectionService:_count(target: string): number
	local n = 0
	for _, role in self.roles do
		if role == target then
			n += 1
		end
	end
	return n
end

function InfectionService:GetSurvivorCount(): number
	return self:_count(GameConfig.ROLE_SURVIVOR)
end

function InfectionService:GetInfectedCount(): number
	return self:_count(GameConfig.ROLE_INFECTED)
end

function InfectionService:GetConversions(): number
	return self.conversions
end

return InfectionService
