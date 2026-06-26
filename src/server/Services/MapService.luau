--[[
	MapService (service)
	--------------------
	Builds a persistent HUB (spawn / socialize / queue) and a per-match ARENA that
	is REBUILT each round from one of several layouts (see MapConfig) — random map
	rotation (Phase 6). Both live in a single place; players move between them by
	CFrame. Exposes the queue pad + alarm light for the hub spectacle, the objective
	geometry for ObjectiveService, and hazard zones for InfectionService.

	Structure: Workspace.GameMap holds the persistent hub parts + an "Arena" folder
	that LoadMap destroys and rebuilds each match. Objective state Attributes live on
	GameMap (which persists), so the client HUD keeps its subscription across maps.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brand = require(ReplicatedStorage:WaitForChild("Brand"))
local Config = ReplicatedStorage:WaitForChild("Config")
local MapConfig = require(Config:WaitForChild("MapConfig"))
local ObjectiveConfig = require(Config:WaitForChild("ObjectiveConfig"))

local MapService = {}

local WALL_HEIGHT = 25
local ARENA_CENTER = Vector3.new(0, 0, 0)
local HUB_CENTER = Vector3.new(0, 0, 600) -- well clear of the arena

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- == Per-match arena geometry (rebuilt by LoadMap) ===========================

local function buildArena(parent: Folder, def: any)
	local size = MapConfig.SIZE
	makePart({
		Name = "Floor",
		Size = Vector3.new(size, 2, size),
		Position = ARENA_CENTER + Vector3.new(0, -1, 0),
		Color = def.floorColor,
		Material = Enum.Material.Concrete,
		Parent = parent,
	})

	local half = size / 2
	local walls = {
		{ Size = Vector3.new(size, WALL_HEIGHT, 2), Offset = Vector3.new(0, WALL_HEIGHT / 2, -half) },
		{ Size = Vector3.new(size, WALL_HEIGHT, 2), Offset = Vector3.new(0, WALL_HEIGHT / 2, half) },
		{ Size = Vector3.new(2, WALL_HEIGHT, size), Offset = Vector3.new(-half, WALL_HEIGHT / 2, 0) },
		{ Size = Vector3.new(2, WALL_HEIGHT, size), Offset = Vector3.new(half, WALL_HEIGHT / 2, 0) },
	}
	for _, w in walls do
		makePart({
			Name = "Wall",
			Size = w.Size,
			Position = ARENA_CENTER + w.Offset,
			Color = def.accent, -- accent the walls so each map reads as distinct at a glance
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end

	for _, pos in def.cover do
		makePart({
			Name = "Cover",
			Size = Vector3.new(14, 10, 14),
			Position = ARENA_CENTER + pos,
			Color = def.coverColor,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end
end

-- The Phase-5 objective props for this map: generators + the central extraction pad.
-- Geometry only; ObjectiveService owns prompts/beacons/colors at match time.
local function buildObjectives(parent: Folder, def: any): ({ BasePart }, BasePart)
	local generators = {}
	for i, pos in def.generators do
		local gen = makePart({
			Name = "Generator" .. i,
			Size = Vector3.new(8, 10, 8),
			Position = ARENA_CENTER + pos,
			Color = Brand.Color.HazardYellow,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			Parent = parent,
		})
		local light = Instance.new("PointLight")
		light.Color = Brand.Color.HazardYellow
		light.Brightness = 4
		light.Range = 26
		light.Enabled = false
		light.Parent = gen
		generators[i] = gen
	end

	local pad = makePart({
		Name = "ExtractPad",
		Size = Vector3.new(18, 1, 18),
		Position = ARENA_CENTER + MapConfig.EXTRACT_CENTER,
		Color = Brand.Color.Panel,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
		CanQuery = false, -- thin floor slab: keep it out of weapon raycasts (still solid to stand on)
		Parent = parent,
	})
	local padLight = Instance.new("PointLight")
	padLight.Name = "PadLight"
	padLight.Color = Brand.Color.SafeGreen
	padLight.Brightness = 6
	padLight.Range = 50
	padLight.Enabled = false
	padLight.Parent = pad

	return generators, pad
end

-- Contamination zones: flat pink neon patches you walk through. Returns the
-- {center,radius} list MapService uses for InHazard tests.
local function buildHazards(parent: Folder, def: any): { { center: Vector3, radius: number } }
	local zones = {}
	for i, h in def.hazards do
		local center = ARENA_CENTER + h.center
		makePart({
			Name = "Hazard" .. i,
			Size = Vector3.new(h.radius * 2, 0.4, h.radius * 2),
			Position = center,
			Color = Brand.Color.InfectedPink,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			CanCollide = false, -- walk through it
			CanQuery = false, -- and keep it out of weapon raycasts (detection is pure distance math)
			Parent = parent,
		})
		zones[i] = { center = center, radius = h.radius }
	end
	return zones
end

-- == Persistent hub ==========================================================

-- Builds the hub and RETURNS (queuePad, alarmLight) for the matchmaking spectacle.
local function buildHub(parent: Folder): (BasePart, PointLight)
	makePart({
		Name = "HubFloor",
		Size = Vector3.new(100, 2, 100),
		Position = HUB_CENTER + Vector3.new(0, -1, 0),
		Color = Brand.Color.BgDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = HUB_CENTER
	spawn.Color = Color3.fromRGB(80, 140, 220)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Parent = parent

	-- The queue pad: big, unmistakable, GREEN (readability rule = "go / join").
	local pad = makePart({
		Name = "QueuePad",
		Size = Vector3.new(16, 1, 16),
		Position = HUB_CENTER + Vector3.new(0, 0.5, -28),
		Color = Brand.Color.SafeGreen,
		Material = Enum.Material.Neon,
		Parent = parent,
	})

	-- Alarm beacon (off until the queue pops), saturated pink = "danger".
	local beacon = makePart({
		Name = "AlarmBeacon",
		Size = Vector3.new(3, 3, 3),
		Position = HUB_CENTER + Vector3.new(0, 20, -28),
		Color = Brand.Color.InfectedPink,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		Parent = parent,
	})
	local light = Instance.new("PointLight")
	light.Color = Brand.Color.InfectedPink
	light.Brightness = 6
	light.Range = 40
	light.Enabled = false
	light.Parent = beacon

	return pad, light
end

-- == Lifecycle ===============================================================

function MapService:Initialize()
	-- Fresh start (a stale GameMap should never exist on a live server, but if a
	-- Studio session left one, rebuild clean rather than re-resolve piecemeal).
	local stale = Workspace:FindFirstChild("GameMap")
	if stale then
		stale:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "GameMap"
	local pad, light = buildHub(folder)
	folder.Parent = Workspace

	self.mapFolder = folder
	self.queuePad = pad
	self.alarmLight = light
	self.generators = {} :: { BasePart }
	self.extractPad = nil :: BasePart?
	self.hazards = {} :: { { center: Vector3, radius: number } }
	self.arenaSpawns = {} :: { CFrame }
	self._lastMapIndex = 0

	-- Build an initial arena so the world isn't empty before the first match.
	self:LoadRandomMap()
end

-- Rebuilds the arena (keeping the persistent hub) from a map definition.
function MapService:LoadMap(def: any)
	-- Fail loud if a map is misconfigured: too few generators = a silently unwinnable map.
	assert(
		#def.generators == ObjectiveConfig.GEN_COUNT,
		("MapConfig '%s' must define exactly %d generators"):format(def.name, ObjectiveConfig.GEN_COUNT)
	)
	local old = self.mapFolder:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end
	local arena = Instance.new("Folder")
	arena.Name = "Arena"

	buildArena(arena, def)
	local gens, pad = buildObjectives(arena, def)
	local zones = buildHazards(arena, def)
	arena.Parent = self.mapFolder

	self.generators = gens
	self.extractPad = pad
	self.hazards = zones
	self.currentMap = def

	self.arenaSpawns = {}
	for _, p in def.spawns do
		table.insert(self.arenaSpawns, CFrame.new(ARENA_CENTER + p + Vector3.new(0, 5, 0)))
	end

	self.mapFolder:SetAttribute("MapName", def.name)
end

-- Picks a random map (never the same one twice in a row) and loads it.
function MapService:LoadRandomMap(): any
	local maps = MapConfig.maps
	local index = 1
	if #maps > 1 then
		repeat
			index = math.random(1, #maps)
		until index ~= self._lastMapIndex
	end
	self._lastMapIndex = index
	self:LoadMap(maps[index])
	return maps[index]
end

-- True if a position is inside any active contamination zone (horizontal test).
function MapService:InHazard(pos: Vector3): boolean
	for _, z in self.hazards do
		local d = Vector3.new(pos.X - z.center.X, 0, pos.Z - z.center.Z).Magnitude
		if d <= z.radius then
			return true
		end
	end
	return false
end

-- == Player placement ========================================================

local function placeCharacter(player: Player, cframe: CFrame)
	-- Async + WAIT for the HumanoidRootPart so the move can't silently no-op and
	-- strand the player (Phase 1 review fix).
	task.spawn(function()
		local char = player.Character
		if not char then
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
		if hrp and player.Character == char then
			char:PivotTo(cframe)
		end
	end)
end

function MapService:SendToArena(player: Player, index: number)
	local spawns = self.arenaSpawns
	if #spawns == 0 then
		return
	end
	local cf = spawns[((index - 1) % #spawns) + 1]
	placeCharacter(player, cf)
end

function MapService:SendToHub(player: Player)
	local jitter = Vector3.new(math.random(-30, 30), 5, math.random(-10, 30))
	placeCharacter(player, CFrame.new(HUB_CENTER + jitter))
end

-- == Objective geometry accessors ============================================

function MapService:GetGenerators(): { BasePart }
	return self.generators
end

function MapService:GetExtractPad(): BasePart?
	return self.extractPad
end

function MapService:GetMapFolder(): Folder?
	return self.mapFolder
end

return MapService
