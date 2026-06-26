--[[
	MapService (service)
	--------------------
	Builds a persistent HUB and a per-match ARENA rebuilt each round from one of the
	MapConfig layouts (random rotation). Beyond the gameplay geometry it now layers in
	map ENRICHMENT — varied cover, platforms + ramps (verticality), neon trim/decals,
	objective framing (gen floor-rings + an extract beacon column), and a per-map
	ATMOSPHERE (global Lighting state) applied while the roster is in the arena and
	restored to a bright hub baseline on return (the hub shares the one Lighting service).

	Structure: Workspace.GameMap holds the persistent hub + an "Arena" folder LoadMap
	destroys/rebuilds each match. Objective Attributes live on GameMap (persists).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

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

-- A WedgePart twin of makePart (for walk-up ramps).
local function makeWedge(props: { [string]: any }): WedgePart
	local part = Instance.new("WedgePart")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- Pure decoration: CanCollide=false AND CanQuery=false BY DEFAULT so a thin part can
-- never block movement OR weapon raycasts (the known non-collidable-still-blocks-raycasts
-- bug). Callers can override, but decoration is raycast-safe by construction.
local function makeDecor(props: { [string]: any }): Part
	local merged: { [string]: any } = { CanCollide = false, CanQuery = false }
	for key, value in props do
		merged[key] = value
	end
	return makePart(merged)
end

-- == Per-match arena geometry (rebuilt by LoadMap) ===========================

local function buildArena(parent: Folder, def: any)
	local size = MapConfig.SIZE
	makePart({
		Name = "Floor",
		Size = Vector3.new(size, 2, size),
		Position = ARENA_CENTER + Vector3.new(0, -1, 0),
		Color = def.floorColor,
		Material = def.floorMaterial or Enum.Material.Concrete,
		Parent = parent,
	})

	local half = size / 2
	local wallMat = def.wallMaterial or Enum.Material.Metal
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
			Color = def.accent, -- accent the walls so each map reads as distinct
			Material = wallMat,
			Parent = parent,
		})
	end

	-- Cover: varied-size blocks (coverBlocks) or the legacy flat 14x10x14 list.
	local coverMat = def.coverMaterial or Enum.Material.Metal
	if def.coverBlocks then
		for _, c in def.coverBlocks do
			local props: { [string]: any } =
				{ Name = "Cover", Size = c.size, Color = def.coverColor, Material = coverMat, Parent = parent }
			if c.rot and c.rot ~= 0 then
				-- Pass ONLY CFrame for rotated blocks (makePart is last-write-wins; never mix with Position).
				props.CFrame = CFrame.new(ARENA_CENTER + c.pos) * CFrame.Angles(0, math.rad(c.rot), 0)
			else
				props.Position = ARENA_CENTER + c.pos
			end
			makePart(props)
		end
	elseif def.cover then
		for _, pos in def.cover do
			makePart({
				Name = "Cover",
				Size = Vector3.new(14, 10, 14),
				Position = ARENA_CENTER + pos,
				Color = def.coverColor,
				Material = coverMat,
				Parent = parent,
			})
		end
	end
end

-- Walkable raised decks (collidable + queryable: stand + shoot from them).
local function buildPlatforms(parent: Folder, def: any)
	if not def.platforms then
		return
	end
	for _, p in def.platforms do
		makePart({
			Name = "Platform",
			Size = p.size,
			Position = ARENA_CENTER + p.pos,
			Color = if p.glass then def.accent else def.coverColor,
			Material = if p.glass then Enum.Material.SmoothPlastic else Enum.Material.Metal,
			Transparency = if p.glass then 0.4 else 0,
			Parent = parent,
		})
	end
end

-- WedgePart access to platforms (collidable, jumpable).
local function buildRamps(parent: Folder, def: any)
	if not def.ramps then
		return
	end
	for _, r in def.ramps do
		makeWedge({
			Name = "Ramp",
			Size = r.size,
			CFrame = CFrame.new(ARENA_CENTER + r.pos) * CFrame.Angles(0, math.rad(r.rot or 0), 0),
			Color = def.coverColor,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end
end

-- Pure-decoration neon (trim caps, glowing orbs). Raycast-safe via makeDecor.
local function buildDecals(parent: Folder, def: any)
	if not def.decals then
		return
	end
	for _, d in def.decals do
		makeDecor({
			Name = "Decal",
			Size = d.size,
			Position = ARENA_CENTER + d.pos,
			Color = if d.color == "accent" then def.accent else def.coverColor,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			Shape = if d.shape == "orb" then Enum.PartType.Ball else Enum.PartType.Block,
			Parent = parent,
		})
	end
end

-- Emissive wall trim (neon strips, no light instances) + a few wall light-posts for
-- actual illumination. Kept lean for low-end mobile.
local function buildPerimeter(parent: Folder, def: any)
	local size = MapConfig.SIZE
	local half = size / 2
	local strips = {
		{ p = Vector3.new(0, 1, -half + 0.5), s = Vector3.new(size, 0.6, 0.3) },
		{ p = Vector3.new(0, 1, half - 0.5), s = Vector3.new(size, 0.6, 0.3) },
		{ p = Vector3.new(-half + 0.5, 1, 0), s = Vector3.new(0.3, 0.6, size) },
		{ p = Vector3.new(half - 0.5, 1, 0), s = Vector3.new(0.3, 0.6, size) },
		{ p = Vector3.new(0, WALL_HEIGHT - 1, -half + 0.5), s = Vector3.new(size, 0.6, 0.3) },
		{ p = Vector3.new(0, WALL_HEIGHT - 1, half - 0.5), s = Vector3.new(size, 0.6, 0.3) },
		{ p = Vector3.new(-half + 0.5, WALL_HEIGHT - 1, 0), s = Vector3.new(0.3, 0.6, size) },
		{ p = Vector3.new(half - 0.5, WALL_HEIGHT - 1, 0), s = Vector3.new(0.3, 0.6, size) },
	}
	for _, st in strips do
		makeDecor({
			Name = "Trim",
			Size = st.s,
			Position = ARENA_CENTER + st.p,
			Color = def.accent,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			Parent = parent,
		})
	end

	local postSpots = {
		Vector3.new(-half + 4, 9, -half + 4),
		Vector3.new(half - 4, 9, -half + 4),
		Vector3.new(-half + 4, 9, half - 4),
		Vector3.new(half - 4, 9, half - 4),
		Vector3.new(0, 9, -half + 4),
		Vector3.new(0, 9, half - 4),
	}
	for _, sp in postSpots do
		local post = makePart({
			Name = "LightPost",
			Size = Vector3.new(1.5, 18, 1.5),
			Position = ARENA_CENTER + sp,
			Color = def.coverColor,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		local pl = Instance.new("PointLight")
		pl.Color = def.accentLight or def.accent
		pl.Brightness = 2
		pl.Range = 40
		pl.Shadows = false
		pl.Parent = post
	end
end

-- The Phase-5 objective props: generators + the central extraction pad (geometry only).
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

-- Readability framing built AFTER buildObjectives (reuses the real refs): a glowing
-- floor ring under each generator + a tall translucent column on the extract pad, so
-- objectives POP through fog/over cover. All raycast-safe (makeDecor).
local function buildObjectiveFraming(parent: Folder, gens: { BasePart }, pad: BasePart?)
	for _, gen in gens do
		if gen then
			makeDecor({
				Name = "GenRing",
				Size = Vector3.new(16, 0.3, 16),
				Position = gen.Position - Vector3.new(0, 4.85, 0), -- flat on the floor under the gen
				Color = Brand.Color.HazardYellow,
				Material = Enum.Material.Neon,
				Transparency = 0.55,
				Parent = parent,
			})
		end
	end
	if pad then
		makeDecor({
			Name = "ExtractBeam",
			Size = Vector3.new(3, 40, 3),
			Position = pad.Position + Vector3.new(0, 20, 0),
			Color = Brand.Color.SafeGreen,
			Material = Enum.Material.Neon,
			Transparency = 0.85,
			Parent = parent,
		})
	end
end

local function buildDecor(parent: Folder, def: any)
	buildPerimeter(parent, def)
	buildDecals(parent, def)
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

-- == Atmosphere (global Lighting, tracked to player LOCATION not geometry) ====

function MapService:_applyLighting(s: any)
	Lighting.ClockTime = s.clockTime
	Lighting.Brightness = s.brightness
	Lighting.Ambient = s.ambient
	Lighting.OutdoorAmbient = s.outdoorAmbient
	Lighting.FogColor = s.fogColor
	Lighting.FogStart = s.fogStart
	Lighting.FogEnd = s.fogEnd
	self._cc.TintColor = s.ccTint
	self._cc.Saturation = s.ccSaturation
	self._cc.Brightness = s.ccBrightness
	self._cc.Contrast = s.ccContrast
	if s.atmosphere then
		self._atmos.Density = s.atmosphere.density
		self._atmos.Haze = s.atmosphere.haze
		self._atmos.Color = s.atmosphere.color
		self._atmos.Parent = Lighting
	else
		self._atmos.Parent = nil
	end
end

-- Applied at MATCH START (roster now in the arena) — NOT in LoadMap, which runs during
-- Prep while players may still be in the hub queue.
function MapService:ApplyMatchAtmosphere()
	self:_applyLighting((self.currentMap and self.currentMap.lighting) or MapConfig.HUB_LIGHTING)
end

-- Restored when the roster returns to the hub.
function MapService:RestoreHubLighting()
	self:_applyLighting(MapConfig.HUB_LIGHTING)
end

-- == Lifecycle ===============================================================

function MapService:Initialize()
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

	-- Single shared lighting effects, reused across maps (created once).
	self._cc = Instance.new("ColorCorrectionEffect")
	self._cc.Name = "OZColorCorrection"
	self._cc.Parent = Lighting
	self._atmos = Instance.new("Atmosphere")
	self._atmos.Name = "OZAtmosphere"
	self:RestoreHubLighting() -- start neutral/bright

	-- Build an initial arena so the world isn't empty before the first match.
	self:LoadRandomMap()
end

-- Regression guard for the cover-on-spawn bug class: warn (loud, never silent) if a
-- spawn point sits inside a solid's footprint. Conservative AABB (ignores rotation).
function MapService:_warnSpawnOverlaps(def: any)
	local solids = {}
	local function add(list)
		if not list then
			return
		end
		for _, e in list do
			table.insert(solids, { pos = e.pos, size = e.size })
		end
	end
	add(def.coverBlocks)
	add(def.platforms)
	add(def.ramps)
	for _, sp in def.spawns do
		for _, s in solids do
			if math.abs(sp.X - s.pos.X) < s.size.X / 2 + 3 and math.abs(sp.Z - s.pos.Z) < s.size.Z / 2 + 3 then
				warn(
					("[MapService] '%s': spawn (%d,%d) overlaps a solid at (%d,%d)"):format(
						def.name,
						sp.X,
						sp.Z,
						s.pos.X,
						s.pos.Z
					)
				)
			end
		end
	end
end

-- Rebuilds the arena (keeping the persistent hub) from a map definition.
function MapService:LoadMap(def: any)
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
	buildPlatforms(arena, def)
	buildRamps(arena, def)
	local gens, pad = buildObjectives(arena, def)
	buildObjectiveFraming(arena, gens, pad)
	local zones = buildHazards(arena, def)
	buildDecor(arena, def)
	arena.Parent = self.mapFolder

	self.generators = gens
	self.extractPad = pad
	self.hazards = zones
	self.currentMap = def

	self.arenaSpawns = {}
	for _, p in def.spawns do
		table.insert(self.arenaSpawns, CFrame.new(ARENA_CENTER + p + Vector3.new(0, 5, 0)))
	end

	self:_warnSpawnOverlaps(def)
	self.mapFolder:SetAttribute("MapName", def.name)
end

-- Picks a random map (never the same one twice in a row) and loads it.
function MapService:LoadRandomMap(): any
	local maps = MapConfig.maps
	local index = 1
	if #maps > 1 then
		-- Pick a different map than last time, capped so an unlucky RNG run can't stall.
		local attempts = 0
		repeat
			index = math.random(1, #maps)
			attempts += 1
		until index ~= self._lastMapIndex or attempts >= 50
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
