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
	self.map = services.MapService
	self.stats = services.StatsService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))

	self.roles = {} :: { [Player]: string? }
	self.isPatientZero = {} :: { [Player]: boolean }
	self.infection = {} :: { [Player]: number } -- 0-100, survivors only
	self.downed = {} :: { [Player]: boolean }
	self.downedSince = {} :: { [Player]: number }
	self.immuneUntil = {} :: { [Player]: number }
	self.lastContact = {} :: { [Player]: number }
	self.rescuePrompts = {} :: { [Player]: ProximityPrompt }
	self.playerConns = {} :: { [Player]: { RBXScriptConnection } }
	self.roundActive = false
	self.conversions = 0
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
		hum.WalkSpeed = self.classes:GetWalkSpeed(player, role) + (player:GetAttribute("CloakSpeedBonus") or 0)
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

local function anyWithin(positions: { Vector3 }, target: Vector3, range: number): boolean
	for _, pos in positions do
		if (pos - target).Magnitude <= range then
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
	player:SetAttribute("Downed", false)
	player:SetAttribute("Infection", 0)
	self:_removePrompt(player)
	self.teams:ToInfected(player)
	self.combat:RemoveLoadout(player)
	self.combat:InitInfected(player)
	self:_applyMovement(player)

	self.net.Notify:FireClient(player, "You've turned! Hunt the survivors.")
end

-- == The driving loop ========================================================

function InfectionService:_tick(dt: number)
	local now = os.clock()
	-- Safe to iterate: _convert only rewrites an existing self.roles VALUE; nothing
	-- here may ADD or REMOVE self.roles keys during the loop.
	local infectedPos = self:_infectedPositions()

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
				local immune = self:_isImmune(player)
				local current = self.infection[player] or 0
				local contact = anyWithin(infectedPos, hrp.Position, InfectionConfig.CONTACT_RANGE)
				local hazard = self.map ~= nil and self.map:InHazard(hrp.Position)
				if contact or hazard then
					self.lastContact[player] = now
					if not immune then
						-- contact and/or hazard both fill; immunity blocks GAIN, not decay
						local rate = (contact and InfectionConfig.FILL_RATE or 0)
							+ (hazard and InfectionConfig.HAZARD_FILL_RATE or 0)
						current += rate * dt
					end
				elseif now - (self.lastContact[player] or 0) >= InfectionConfig.DECAY_DELAY then
					current -= InfectionConfig.DECAY_RATE * dt
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
		self.combat:GiveLoadout(player) -- re-issue weapons on a fresh body
	elseif self.roundActive and self.roles[player] == GameConfig.ROLE_INFECTED then
		-- Stunned survives respawn (drives the freeze + pending recover); re-create
		-- the stun highlight that died with the old character.
		self.combat:RefreshStun(player)
	end
	self:_applyMovement(player)
end

function InfectionService:OnPlayerRemoving(player: Player)
	self:_removePrompt(player)
	if self.playerConns[player] then
		disconnectAll(self.playerConns[player])
	end
	self.playerConns[player] = nil
	self.roles[player] = nil
	self.isPatientZero[player] = nil
	self.infection[player] = nil
	self.downed[player] = nil
	self.downedSince[player] = nil
	self.immuneUntil[player] = nil
	self.lastContact[player] = nil
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

	for _, player in roster do
		self.isPatientZero[player] = chosen[player] == true
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
	end

	self:_startLoop()
end

function InfectionService:EndRound(roster: { Player })
	self.roundActive = false
	for _, player in roster do
		self:_removePrompt(player)
		self.combat:ClearCombat(player)
		self.roles[player] = nil
		self.isPatientZero[player] = false
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

-- Ability hooks (Phase 4): adjust a survivor's infection meter.
function InfectionService:AddInfection(player: Player, amount: number)
	if self.roles[player] ~= GameConfig.ROLE_SURVIVOR or self.downed[player] or self:_isImmune(player) then
		return
	end
	self:_setInfection(player, (self.infection[player] or 0) + amount)
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
