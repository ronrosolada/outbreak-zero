--[[
	HazardService (service) — Increment 2b
	--------------------------------------
	Drives the design maps' DYNAMIC hazards (the "fun hooks"):
	  - Line 0 TRAIN: a car that sweeps the track on a telegraphed timer (3s horn/flash
	    warning, then a fast rush). A direct hit knocks you back and DOWNS survivors.
	  - Funland CAROUSEL: a radial fling + stagger for anyone on the disc.
	  - Third RAIL (electrified): a brief stagger + a little infection on contact.

	Reads MapService:GetDynamicHazards() (arena-space) at match start, builds the train
	actuator + warning beacons into the Arena, and runs ONE generation-guarded loop. This
	deliberately lives OUTSIDE InfectionService:_tick (which must stay yield-free). The
	flooded-room SLOW is handled separately by InfectionService via MapService:HazardSlowMult.

	Server-authoritative. Knockback/stagger hit everyone (chaos is the fun); a train hit
	downs survivors (InfectionService:ForceDown); the rail also ticks a little infection.
	RoundService calls StartHazards() at match start and StopHazards() at round-end.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local HazardService = {}

local TICK = 0.15 -- hazard loop interval (separate from the infection tick)
local SWEEP_SECONDS = 3 -- how long the train takes to cross once it launches
local RAIL_COOLDOWN = 1.5 -- min seconds between rail staggers per player
local CAROUSEL_COOLDOWN = 2 -- min seconds between carousel flings per player

local function getHrp(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

local function knockback(hrp: BasePart, dir: Vector3, force: number, up: number)
	hrp.AssemblyLinearVelocity = dir * force + Vector3.new(0, up, 0)
end

function HazardService:Initialize(services)
	self.map = services.MapService
	self.infection = services.InfectionService
	self.active = false
	self._gen = 0
	self._startClock = 0
	self.hazards = {} :: { any }
	self.train = nil :: BasePart?
	self.warnLights = {} :: { PointLight }
	self.staggerToken = {} :: { [Player]: number }
	self.lastHit = {} :: { [Player]: { [string]: number } }
end

function HazardService:OnPlayerRemoving(player: Player)
	self.staggerToken[player] = nil
	self.lastHit[player] = nil
end

-- True at most once per `cooldown` seconds per (player, key) — so a hazard hits on
-- entry, not every 0.15s tick.
function HazardService:_throttle(player: Player, key: string, cooldown: number): boolean
	local now = os.clock()
	self.lastHit[player] = self.lastHit[player] or {}
	if (self.lastHit[player][key] or -math.huge) + cooldown > now then
		return false
	end
	self.lastHit[player][key] = now
	return true
end

-- Briefly ragdoll/root a character (PlatformStand), token-guarded so overlapping
-- staggers don't end early.
function HazardService:_stagger(player: Player, seconds: number)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.PlatformStand = true
	self.staggerToken[player] = (self.staggerToken[player] or 0) + 1
	local token = self.staggerToken[player]
	task.delay(seconds, function()
		if self.staggerToken[player] == token then
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if h then
				h.PlatformStand = false
			end
		end
	end)
end

function HazardService:_carousel(h: any)
	for _, player in Players:GetPlayers() do
		local hrp = getHrp(player)
		if hrp then
			local flat = Vector3.new(hrp.Position.X - h.center.X, 0, hrp.Position.Z - h.center.Z)
			if flat.Magnitude <= h.radius and self:_throttle(player, "carousel", CAROUSEL_COOLDOWN) then
				local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
				knockback(hrp, dir, h.knockback, 30) -- fling outward
				self:_stagger(player, h.stagger)
			end
		end
	end
end

function HazardService:_rail(h: any)
	for _, player in Players:GetPlayers() do
		local hrp = getHrp(player)
		if
			hrp
			and math.abs(hrp.Position.X - h.center.X) <= h.sizeX / 2
			and math.abs(hrp.Position.Z - h.center.Z) <= h.sizeZ / 2
			and self:_throttle(player, "rail", RAIL_COOLDOWN)
		then
			self:_stagger(player, h.stun)
			knockback(hrp, Vector3.new(0, 1, 0), 0, 25) -- a little shock pop (infection comes from the zone fill)
		end
	end
end

function HazardService:_trainStep(h: any, now: number)
	local car = self.train
	if not car then
		return
	end
	local p = (now - self._startClock) % h.period
	if p < h.telegraph then
		-- Telegraph: stage the car at the mouth + flash warning lights so it feels fair.
		car.Transparency = 0.3
		car.CFrame = CFrame.new(h.from)
		local flash = (math.floor(p * 6) % 2) == 0
		for _, lt in self.warnLights do
			lt.Enabled = flash
		end
	elseif p < h.telegraph + SWEEP_SECONDS then
		-- Rush across the track. Overlap = knockback + down (once per sweep, via throttle).
		for _, lt in self.warnLights do
			lt.Enabled = true
		end
		local t = (p - h.telegraph) / SWEEP_SECONDS
		local pos = h.from:Lerp(h.to, t)
		car.Transparency = 0
		car.CFrame = CFrame.new(pos)
		for _, player in Players:GetPlayers() do
			local hrp = getHrp(player)
			if
				hrp
				and math.abs(hrp.Position.X - pos.X) <= h.carSize.X / 2
				and math.abs(hrp.Position.Z - pos.Z) <= h.carSize.Z / 2
				and self:_throttle(player, "train", h.period - 1)
			then
				local pushZ = if hrp.Position.Z >= pos.Z then 1 else -1
				knockback(hrp, Vector3.new(0, 0, pushZ), h.knockback, 40)
				self:_stagger(player, 1.5)
				if h.downed then
					self.infection:ForceDown(player)
				end
			end
		end
	else
		-- Parked off the far end, hidden, until the next cycle.
		car.Transparency = 1
		car.CFrame = CFrame.new(h.to)
		for _, lt in self.warnLights do
			lt.Enabled = false
		end
	end
end

function HazardService:_step()
	local now = os.clock()
	for _, h in self.hazards do
		if h.kind == "Knockback" then
			self:_carousel(h)
		elseif h.kind == "Electrified" then
			self:_rail(h)
		elseif h.kind == "MovingHazard" then
			self:_trainStep(h, now)
		end
	end
end

function HazardService:StartHazards()
	self:StopHazards() -- defensive: never stack two loops / leftover actuators
	local hazards = self.map:GetDynamicHazards()
	if #hazards == 0 then
		return -- centered maps have no dynamic hazards
	end
	self.hazards = hazards
	self.active = true
	self._gen += 1
	local gen = self._gen
	self._startClock = os.clock()

	local arena = self.map:GetArena()
	for _, h in hazards do
		if h.kind == "MovingHazard" and arena then
			local car = Instance.new("Part")
			car.Name = "HazardTrain"
			car.Anchored = true
			car.CanCollide = false -- it passes through the perimeter wall (enters from the tunnel)
			car.CanQuery = false
			car.Size = h.carSize
			car.Color = Brand.Color.HazardYellow
			car.Material = Enum.Material.Neon
			car.Transparency = 1
			car.CFrame = CFrame.new(h.from)
			car.Parent = arena
			self.train = car

			-- Warning beacons where the track meets the play area (flash during telegraph).
			for _, x in { -104, 104 } do
				local beacon = Instance.new("Part")
				beacon.Name = "TrainWarning"
				beacon.Anchored = true
				beacon.CanCollide = false
				beacon.CanQuery = false
				beacon.Size = Vector3.new(2, 16, 2)
				beacon.Position = Vector3.new(x, 8, h.from.Z)
				beacon.Color = Brand.Color.InfectedPink
				beacon.Material = Enum.Material.Neon
				beacon.Parent = arena
				local light = Instance.new("PointLight")
				light.Color = Brand.Color.InfectedPink
				light.Brightness = 6
				light.Range = 30
				light.Enabled = false
				light.Parent = beacon
				table.insert(self.warnLights, light)
			end
		end
	end

	task.spawn(function()
		while self.active and self._gen == gen do
			self:_step()
			task.wait(TICK)
		end
	end)
end

function HazardService:StopHazards()
	self.active = false
	self._gen += 1 -- invalidate any running loop
	if self.train then
		self.train:Destroy()
		self.train = nil
	end
	for _, lt in self.warnLights do
		if lt.Parent then
			lt.Parent:Destroy() -- destroy the beacon part (and its light)
		end
	end
	self.warnLights = {}
	self.hazards = {}
	-- Clear any in-flight stagger BEFORE wiping the token table: the pending un-ragdoll
	-- closures are token-guarded against self.staggerToken, so once we replace the table
	-- they can never fire — a player staggered at match-end would be left frozen.
	for player in self.staggerToken do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
		end
	end
	self.staggerToken = {}
	self.lastHit = {}
end

return HazardService
