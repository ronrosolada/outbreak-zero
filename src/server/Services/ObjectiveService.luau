--[[
	ObjectiveService (service)
	--------------------------
	Phase 5 — the Outbreak objective race. Survivors POWER GEN_COUNT generators
	(hold a ProximityPrompt), which ARMS the central extraction pad; then all living
	survivors hold the pad together for EXTRACT_HOLD_SECONDS to ESCAPE and win.

	Each generator powered fires a team-wide CLEANSE PULSE (InfectionService) — the
	readable anti-snowball comeback.

	Server-authoritative. Objective state is mirrored to Attributes on the GameMap
	folder so the HUD reacts via GetAttributeChangedSignal (no new Net remotes).
	The per-frame extraction progress is driven by InfectionService:_tick calling
	:Tick (so we reuse its already-computed infected positions and avoid a 2nd loop).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local ObjectiveConfig = require(Config:WaitForChild("ObjectiveConfig"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local ObjectiveService = {}

local function getRootPart(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

-- World-space "look here" beacon (mirrors the InfectionService downed beacon).
local function makeBeacon(parent: BasePart, text: string, color: Color3)
	if parent:FindFirstChild("ObjectiveBeacon") then
		return
	end
	local beacon = Instance.new("BillboardGui")
	beacon.Name = "ObjectiveBeacon"
	beacon.Size = UDim2.fromOffset(170, 58)
	beacon.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	beacon.AlwaysOnTop = true
	beacon.MaxDistance = 300
	beacon.Parent = parent
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Brand.Font.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.25
	label.Text = text
	label.Parent = beacon
end

function ObjectiveService:Initialize(services)
	-- InfectionService precedes ObjectiveService in SERVICE_ORDER, so it's already
	-- in the registry; the reverse back-ref (infection.objectives) is wired in Main.
	self.map = services.MapService
	self.infection = services.InfectionService
	self.classes = services.ClassService
	self.economy = services.EconomyService
	self.stats = services.StatsService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))

	self.active = false
	self.armed = false
	self.complete = false
	self.gensOn = 0
	self.powered = {} :: { [number]: boolean }
	self.progress = 0
	self.roster = {} :: { Player }
	self.prompts = {} :: { ProximityPrompt }
end

function ObjectiveService:_setAttr(name: string, value: any)
	local folder = self.map:GetMapFolder()
	if folder then
		folder:SetAttribute(name, value)
	end
end

-- Strip any leftover prompt/beacon from a part (defensive vs a Studio reload mid-match).
local function clearProps(part: BasePart?)
	if not part then
		return
	end
	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then
		prompt:Destroy()
	end
	local beacon = part:FindFirstChild("ObjectiveBeacon")
	if beacon then
		beacon:Destroy()
	end
end

function ObjectiveService:StartObjectives(roster: { Player })
	self.active = true
	self.armed = false
	self.complete = false
	self.gensOn = 0
	self.powered = {}
	self.progress = 0
	self.roster = roster
	self.prompts = {}

	self:_setAttr("GensTotal", ObjectiveConfig.GEN_COUNT)
	self:_setAttr("GensPowered", 0)
	self:_setAttr("Extraction_Powered", false)
	self:_setAttr("Extraction_Progress", 0)

	local generators = self.map:GetGenerators()
	for i = 1, ObjectiveConfig.GEN_COUNT do
		local gen = generators[i]
		if not gen then
			continue -- explicit count (not generic-for) so a nil hole can't truncate setup
		end
		clearProps(gen)
		gen.Color = Brand.Color.HazardYellow
		local light = gen:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Color = Brand.Color.HazardYellow
			light.Enabled = true
		end
		makeBeacon(gen, "POWER", Brand.Color.HazardYellow)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GeneratorPrompt"
		prompt.ActionText = "POWER UP"
		prompt.ObjectText = "Generator"
		prompt.HoldDuration = ObjectiveConfig.GEN_HOLD_SECONDS
		prompt.MaxActivationDistance = ObjectiveConfig.GEN_RANGE
		prompt.RequiresLineOfSight = false
		prompt.Parent = gen
		local idx = i
		prompt.Triggered:Connect(function(player)
			self:_onGenerator(idx, gen, player)
		end)
		table.insert(self.prompts, prompt)
	end

	-- Extraction pad starts LOCKED (dim, no light, no beacon — so kids do generators first).
	local pad = self.map:GetExtractPad()
	if pad then
		clearProps(pad)
		pad.Color = Brand.Color.Panel
		local light = pad:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Enabled = false
		end
	end
end

function ObjectiveService:_onGenerator(index: number, gen: BasePart, player: Player)
	if not self.active or self.powered[index] then
		return
	end
	-- Only a living, non-downed SURVIVOR can power a generator (mirrors the rescue gate).
	if self.infection:GetRole(player) ~= GameConfig.ROLE_SURVIVOR or self.infection:IsDowned(player) then
		return
	end

	self.powered[index] = true
	self.gensOn += 1
	self:_setAttr("GensPowered", self.gensOn)
	self.net.KillFeed:FireAllClients("generator", tostring(self.gensOn), tostring(ObjectiveConfig.GEN_COUNT))

	-- Done: recolor green, swap the beacon, kill the prompt.
	gen.Color = Brand.Color.SafeGreen
	local light = gen:FindFirstChildWhichIsA("PointLight")
	if light then
		light.Color = Brand.Color.SafeGreen
	end
	clearProps(gen)
	makeBeacon(gen, "DONE", Brand.Color.SafeGreen)

	if player.Parent then
		self.economy:AddCoins(player, ObjectiveConfig.REWARD_GENERATOR)
	end
	self.stats:Add(player, "generators", 1)

	-- The comeback beat: cleanse the whole team + a green flash for survivors only.
	self.infection:CleansePulse(ObjectiveConfig.CLEANSE_RELIEF, ObjectiveConfig.CLEANSE_IMMUNITY)
	local powered = self.gensOn
	for _, p in self.roster do
		if not p.Parent then
			continue
		end
		if self.infection:GetRole(p) == GameConfig.ROLE_SURVIVOR then
			self.net.Spectacle:FireClient(p, "cleanse")
		end
		self.net.Notify:FireClient(p, ("Generator %d/%d powered!"):format(powered, ObjectiveConfig.GEN_COUNT))
	end

	if self.gensOn >= ObjectiveConfig.GEN_COUNT then
		self:_arm()
	end
end

function ObjectiveService:_arm()
	self.armed = true
	self:_setAttr("Extraction_Powered", true)

	local pad = self.map:GetExtractPad()
	if pad then
		pad.Color = Brand.Color.SafeGreen
		local light = pad:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Color = Brand.Color.SafeGreen
			light.Enabled = true
		end
		makeBeacon(pad, "ESCAPE HERE", Brand.Color.SafeGreen)
	end

	for _, p in self.roster do
		if p.Parent then
			self.net.Notify:FireClient(p, "\u{2705} EXTRACTION OPEN — all survivors get to the GREEN pad!")
		end
	end
end

-- Driven by InfectionService:_tick. infectedPos is unused for now (extraction is a
-- pure all-aboard hold) but passed so a future "infected contest the pad" rule is free.
function ObjectiveService:Tick(dt: number, _infectedPos: { Vector3 })
	if not self.active or not self.armed or self.complete then
		return
	end
	local pad = self.map:GetExtractPad()
	if not pad then
		return
	end
	local center = pad.Position

	local totalLiving = 0
	local aboard = 0
	local chargeMult = 1 -- Engineer passive (ObjectiveChargeMult): an Engineer on the pad extracts faster
	for _, player in self.roster do
		if
			player.Parent
			and self.infection:GetRole(player) == GameConfig.ROLE_SURVIVOR
			and not self.infection:IsDowned(player)
		then
			local hrp = getRootPart(player)
			if hrp then
				local flat = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z).Magnitude
				-- A survivor too far from the pad is "left behind": they don't gate the
				-- hold, so one lost/AFK player can't deny the whole team's escape.
				if flat <= ObjectiveConfig.EXTRACT_ABANDON_RANGE then
					totalLiving += 1
					if flat <= ObjectiveConfig.EXTRACT_RANGE then
						aboard += 1
						local m = self.classes:GetPassive(player, GameConfig.ROLE_SURVIVOR).ObjectiveChargeMult
						if m then
							chargeMult = math.max(chargeMult, m)
						end
					end
				end
			end
		end
	end

	-- Escape needs a MAJORITY of the present (within-abandon) survivors on the pad, not
	-- ALL of them — otherwise one lost/AFK player lingering in the 12..75-stud band would
	-- decay the hold forever and hand the round to the infected (the C1 grief case).
	local needed = math.max(1, math.ceil(totalLiving * ObjectiveConfig.EXTRACT_REQUIRED_FRACTION))
	if totalLiving >= 1 and aboard >= needed then
		self.progress = math.min(100, self.progress + (100 / ObjectiveConfig.EXTRACT_HOLD_SECONDS) * chargeMult * dt)
	else
		self.progress = math.max(0, self.progress - ObjectiveConfig.EXTRACT_DECAY * dt)
	end
	self:_setAttr("Extraction_Progress", math.floor(self.progress))

	if self.progress >= 100 then
		self.complete = true
	end
end

function ObjectiveService:IsExtractionComplete(): boolean
	return self.complete == true
end

function ObjectiveService:EndObjectives()
	self.active = false
	self.armed = false
	self.complete = false
	self.progress = 0
	self.gensOn = 0
	self.powered = {}
	self.roster = {}

	for _, prompt in self.prompts do
		if prompt and prompt.Parent then
			prompt:Destroy()
		end
	end
	self.prompts = {}

	local generators = self.map:GetGenerators()
	for i = 1, ObjectiveConfig.GEN_COUNT do
		local gen = generators[i]
		if gen then
			clearProps(gen)
			gen.Color = Brand.Color.HazardYellow
			local light = gen:FindFirstChildWhichIsA("PointLight")
			if light then
				light.Enabled = false
			end
		end
	end

	local pad = self.map:GetExtractPad()
	if pad then
		clearProps(pad)
		pad.Color = Brand.Color.Panel
		local light = pad:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Enabled = false
		end
	end

	self:_setAttr("GensPowered", 0)
	self:_setAttr("Extraction_Powered", false)
	self:_setAttr("Extraction_Progress", 0)
end

return ObjectiveService
