--[[
	MapConfig
	---------
	Phase 6 + map-enrichment: data-driven arena layouts. MapService rebuilds the arena
	from one of these per match (random rotation). Beyond cover/generators/extract/
	spawns/hazards, each map now carries an ATMOSPHERE (per-map global Lighting state),
	varied COVER BLOCKS (silhouette variety), PLATFORMS + RAMPS (verticality), and pure
	DECALS (neon trim/orbs) so it reads as a distinct place — all theme-neutral primitives.

	Positions are arena-space (centered on 0,0,0; half-size 110; floor top y=0). Keep-out
	discipline: nothing structural inside the ~58-stud central regroup amphitheater, off
	the center->generator lines, off the spawn points, and clear of hazard discs.
	rot fields are Y-axis degrees. coverBlocks/platforms/ramps are solid (collidable +
	queryable); decals are pure decoration (MapService builds them CanCollide/CanQuery=false).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

-- Per-map spawn points (placed by index). Kept clear of that map's solids + hazards.
local RING = { -- Grid Sector: diagonal ring
	Vector3.new(-20, 0, -20),
	Vector3.new(20, 0, -20),
	Vector3.new(-20, 0, 20),
	Vector3.new(20, 0, 20),
	Vector3.new(0, 0, -25),
	Vector3.new(0, 0, 25),
	Vector3.new(-25, 0, 0),
	Vector3.new(25, 0, 0),
}

local CARGO_SPAWNS = { -- Cargo Bay: central aisle (cover sits at |z|>=46)
	Vector3.new(-30, 0, -12),
	Vector3.new(-12, 0, -12),
	Vector3.new(12, 0, -12),
	Vector3.new(30, 0, -12),
	Vector3.new(-30, 0, 12),
	Vector3.new(-12, 0, 12),
	Vector3.new(12, 0, 12),
	Vector3.new(30, 0, 12),
}

local BIO_SPAWNS = { -- Bio-Dome: on the axes (cover is off-axis)
	Vector3.new(0, 0, -18),
	Vector3.new(0, 0, 18),
	Vector3.new(-18, 0, 0),
	Vector3.new(18, 0, 0),
	Vector3.new(0, 0, -34),
	Vector3.new(0, 0, 34),
	Vector3.new(-34, 0, 0),
	Vector3.new(34, 0, 0),
}

local MapConfig = {}

MapConfig.SIZE = 220 -- arena floor/walls are square at this size for every map
MapConfig.EXTRACT_CENTER = Vector3.new(0, 1, 0) -- the extraction pad sits dead-center on every map

-- Neutral, bright baseline restored whenever players are in the HUB (the hub shares the
-- one global Lighting service with the arena, so MapService applies a map's atmosphere
-- only while the roster is in the arena and restores THIS on the way back).
MapConfig.HUB_LIGHTING = {
	clockTime = 14,
	brightness = 2,
	ambient = Color3.fromRGB(70, 70, 80),
	outdoorAmbient = Color3.fromRGB(90, 90, 100),
	fogColor = Color3.fromRGB(120, 120, 140),
	fogStart = 0,
	fogEnd = 100000, -- fog effectively off in the hub
	ccTint = Color3.fromRGB(255, 255, 255),
	ccSaturation = 0,
	ccBrightness = 0,
	ccContrast = 0,
	atmosphere = nil,
}

MapConfig.maps = {
	{
		name = "Grid Sector",
		theme = "grid",
		accent = Brand.Color.HumanBlue,
		floorColor = Brand.Color.BgDeep,
		coverColor = Brand.Color.Panel,
		floorMaterial = Enum.Material.Concrete,
		wallMaterial = Enum.Material.Metal,
		coverMaterial = Enum.Material.Metal,
		accentLight = Brand.Color.HumanBlue,
		lighting = { -- cool blue, but BRIGHT + sunlit (color via tint/fog, not darkness)
			clockTime = 14,
			brightness = 2.2,
			ambient = Color3.fromRGB(95, 100, 120),
			outdoorAmbient = Color3.fromRGB(110, 115, 135),
			fogColor = Color3.fromRGB(90, 110, 150),
			fogStart = 120,
			fogEnd = 320,
			ccTint = Color3.fromRGB(190, 215, 255),
			ccSaturation = 0.06,
			ccBrightness = 0.04,
			ccContrast = 0.08,
		},
		coverBlocks = { -- two data-server stacks (silhouette variety) + four lane blocks
			{ pos = Vector3.new(-72, 6, 15), size = Vector3.new(16, 12, 16) },
			{ pos = Vector3.new(-72, 12, 19), size = Vector3.new(8, 8, 8) },
			{ pos = Vector3.new(-66, 9, 15), size = Vector3.new(6, 18, 6) },
			{ pos = Vector3.new(72, 6, -15), size = Vector3.new(16, 12, 16) },
			{ pos = Vector3.new(72, 12, -19), size = Vector3.new(8, 8, 8) },
			{ pos = Vector3.new(66, 9, -15), size = Vector3.new(6, 18, 6) },
			{ pos = Vector3.new(-50, 5, -40), size = Vector3.new(14, 10, 14) },
			{ pos = Vector3.new(22, 5, -58), size = Vector3.new(14, 10, 14) }, -- moved off the (45,-38) hazard
			{ pos = Vector3.new(-18, 5, 58), size = Vector3.new(14, 10, 14) }, -- moved off the (-45,38) hazard
			{ pos = Vector3.new(60, 5, 30), size = Vector3.new(14, 10, 14) },
		},
		platforms = { { pos = Vector3.new(0, 12, -74), size = Vector3.new(36, 1, 8), glass = true } },
		ramps = {
			{ pos = Vector3.new(-19, 8, -74), size = Vector3.new(12, 8, 8), rot = 90 },
			{ pos = Vector3.new(19, 8, -74), size = Vector3.new(12, 8, 8), rot = -90 },
		},
		decals = { -- holo-orbs (slab "caps" removed: they floated over the irregular stack tops)
			{ pos = Vector3.new(-50, 12, -40), size = Vector3.new(3, 3, 3), shape = "orb", color = "accent" },
			{ pos = Vector3.new(60, 12, 30), size = Vector3.new(3, 3, 3), shape = "orb", color = "accent" },
		},
		generators = {
			Vector3.new(-80, 5, -80),
			Vector3.new(80, 5, 80),
			Vector3.new(85, 5, -85),
		},
		hazards = {
			{ center = Vector3.new(-45, 1, 38), radius = 13 },
			{ center = Vector3.new(45, 1, -38), radius = 13 },
		},
		spawns = RING,
	},
	{
		name = "Cargo Bay",
		theme = "cargo",
		accent = Brand.Color.HazardYellow,
		floorColor = Brand.Color.BgDeep,
		coverColor = Brand.Color.Panel,
		floorMaterial = Enum.Material.Pavement,
		wallMaterial = Enum.Material.Metal,
		coverMaterial = Enum.Material.Metal,
		accentLight = Brand.Color.HazardYellow,
		lighting = { -- warm amber, BRIGHT daylight dock
			clockTime = 13.5,
			brightness = 2.2,
			ambient = Color3.fromRGB(110, 100, 82),
			outdoorAmbient = Color3.fromRGB(120, 108, 86),
			fogColor = Color3.fromRGB(120, 100, 70),
			fogStart = 130,
			fogEnd = 340,
			ccTint = Color3.fromRGB(255, 238, 200),
			ccSaturation = 0.05,
			ccBrightness = 0.04,
			ccContrast = 0.10,
		},
		coverBlocks = { -- shipping-container canyons flanking the central aisle (|z|>=46)
			{ pos = Vector3.new(-70, 6, -58), size = Vector3.new(20, 12, 10) },
			{ pos = Vector3.new(-44, 6, -58), size = Vector3.new(20, 12, 10) },
			{ pos = Vector3.new(44, 6, -58), size = Vector3.new(20, 12, 10) },
			{ pos = Vector3.new(70, 6, -58), size = Vector3.new(20, 12, 10) },
			{ pos = Vector3.new(-44, 6, 58), size = Vector3.new(20, 12, 10) },
			{ pos = Vector3.new(44, 6, 58), size = Vector3.new(20, 12, 10) },
			{ pos = Vector3.new(-78, 6, 46), size = Vector3.new(20, 12, 10) },
			{ pos = Vector3.new(-74, 18, 50), size = Vector3.new(18, 12, 10) }, -- climbable step
		},
		-- NE-corner overlook (clear of containers/gens/aisle), one gentle walk-up ramp
		-- from the floor (rise 8 / run 14 ~ 30deg, base on the floor).
		platforms = { { pos = Vector3.new(74, 8, 30), size = Vector3.new(16, 1, 12) } },
		ramps = {
			{ pos = Vector3.new(74, 4, 18), size = Vector3.new(10, 8, 14), rot = 0 },
		},
		decals = { -- container roof-trim (0.5 proud) + orbs on the cap-less containers
			{ pos = Vector3.new(-70, 12.75, -58), size = Vector3.new(20, 0.5, 10), color = "accent" },
			{ pos = Vector3.new(70, 12.75, -58), size = Vector3.new(20, 0.5, 10), color = "accent" },
			{ pos = Vector3.new(-44, 12.75, 58), size = Vector3.new(20, 0.5, 10), color = "accent" },
			{ pos = Vector3.new(44, 12.75, 58), size = Vector3.new(20, 0.5, 10), color = "accent" },
			{ pos = Vector3.new(-44, 14, -58), size = Vector3.new(2.5, 2.5, 2.5), shape = "orb", color = "accent" },
			{ pos = Vector3.new(44, 14, -58), size = Vector3.new(2.5, 2.5, 2.5), shape = "orb", color = "accent" },
		},
		generators = {
			Vector3.new(-88, 5, 0),
			Vector3.new(88, 5, 0),
			Vector3.new(0, 5, -88),
		},
		hazards = {
			{ center = Vector3.new(0, 1, 32), radius = 14 },
			{ center = Vector3.new(-55, 1, -30), radius = 12 },
		},
		spawns = CARGO_SPAWNS,
	},
	{
		name = "Bio-Dome",
		theme = "bio",
		accent = Brand.Color.SafeGreen,
		floorColor = Brand.Color.BgDeep,
		coverColor = Brand.Color.Panel,
		floorMaterial = Enum.Material.Grass,
		wallMaterial = Enum.Material.Metal,
		coverMaterial = Enum.Material.Slate,
		accentLight = Brand.Color.SafeGreen,
		lighting = { -- lush green, BRIGHT greenhouse (light haze, not gloom)
			clockTime = 13,
			brightness = 2.1,
			ambient = Color3.fromRGB(95, 120, 100),
			outdoorAmbient = Color3.fromRGB(105, 128, 108),
			fogColor = Color3.fromRGB(90, 150, 110),
			fogStart = 110,
			fogEnd = 300,
			ccTint = Color3.fromRGB(205, 255, 220),
			ccSaturation = 0.14,
			ccBrightness = 0.03,
			ccContrast = 0,
			atmosphere = { density = 0.12, haze = 0.8, color = Color3.fromRGB(200, 230, 210) },
		},
		coverBlocks = { -- rotated "rock mounds" (organic feel), placed CLEAR of the 3 corner hazards
			{ pos = Vector3.new(-58, 4, 48), size = Vector3.new(12, 8, 12), rot = 18 }, -- NW mound
			{ pos = Vector3.new(-52, 7, 52), size = Vector3.new(8, 14, 8), rot = -12 },
			{ pos = Vector3.new(-64, 3, 42), size = Vector3.new(16, 6, 10), rot = 22 },
			{ pos = Vector3.new(60, 4, 18), size = Vector3.new(12, 8, 12), rot = -20 }, -- E mound
			{ pos = Vector3.new(64, 7, 18), size = Vector3.new(8, 14, 8), rot = 15 },
			{ pos = Vector3.new(70, 5, -22), size = Vector3.new(16, 6, 10), rot = -12 }, -- SE-safe mound
			{ pos = Vector3.new(-30, 4, 66), size = Vector3.new(10, 8, 10), rot = 20 }, -- N approach rock
			{ pos = Vector3.new(-66, 5, -8), size = Vector3.new(14, 10, 14) }, -- W side block
			{ pos = Vector3.new(64, 5, 8), size = Vector3.new(14, 10, 14) }, -- E side block
		},
		platforms = { { pos = Vector3.new(0, 8, -86), size = Vector3.new(28, 2, 28) } }, -- south overlook
		ramps = {
			{ pos = Vector3.new(-16, 5, -72), size = Vector3.new(12, 8, 10), rot = 0 },
			{ pos = Vector3.new(16, 5, -72), size = Vector3.new(12, 8, 10), rot = 180 },
		},
		decals = { -- spore pods (vine slab cap removed; orbs lifted clear of the mounds)
			{ pos = Vector3.new(-58, 10, 48), size = Vector3.new(3, 3, 3), shape = "orb", color = "accent" },
			{ pos = Vector3.new(60, 10, 18), size = Vector3.new(3, 3, 3), shape = "orb", color = "accent" },
			{ pos = Vector3.new(-66, 11.5, -8), size = Vector3.new(2.5, 2.5, 2.5), shape = "orb", color = "accent" },
		},
		generators = {
			Vector3.new(0, 5, 92),
			Vector3.new(-90, 5, -62),
			Vector3.new(90, 5, -62),
		},
		hazards = {
			{ center = Vector3.new(-52, 1, -52), radius = 15 },
			{ center = Vector3.new(52, 1, 52), radius = 15 },
			{ center = Vector3.new(52, 1, -52), radius = 12 },
		},
		spawns = BIO_SPAWNS,
	},

	-- ============================ DESIGN BLOCKOUT MAPS ============================
	-- From the design handoff (03_MAPS.md). format="blockout": coords are LOCAL to a
	-- top-left origin (X0 Z0), +X right, +Z down, 220(W)x160(D). MapService converts to
	-- arena space (x-110, z-80) and builds parts/objectives/extraction/hazards from these
	-- tables. Passive hazard effects (Goo/Slow/Electrified fill, LowFriction physics) ship
	-- in this increment; the dynamic ones (train sweep, carousel knockback, rail stun,
	-- flooded slow-move) are driven by HazardService (next increment).
	{
		name = "Funland Carnival",
		format = "blockout",
		localSize = { 220, 160 },
		accent = Brand.Color.HazardYellow,
		floorColor = Color3.fromRGB(46, 44, 70),
		wallColor = Brand.Color.HazardYellow,
		survivorSpawn = "SpawnPlaza",
		lighting = { -- bright, sunny, playful midway
			clockTime = 14,
			brightness = 2.3,
			ambient = Color3.fromRGB(110, 105, 95),
			outdoorAmbient = Color3.fromRGB(125, 120, 110),
			fogColor = Color3.fromRGB(150, 140, 170),
			fogStart = 140,
			fogEnd = 360,
			ccTint = Color3.fromRGB(255, 240, 220),
			ccSaturation = 0.12,
			ccBrightness = 0.05,
			ccContrast = 0.06,
		},
		parts = {
			{
				name = "SpawnPlaza",
				center = { 30, 140 },
				size = { 52, 36 },
				height = 1,
				color = "2EA8FF",
				team = "Survivor",
			},
			{
				name = "FerrisBase",
				center = { 35, 32 },
				size = { 28, 28 },
				height = 3,
				color = "FFFFFF",
				shape = "Cylinder",
			},
			{
				name = "Carousel",
				center = { 72, 70 },
				size = { 44, 44 },
				height = 2,
				color = "FFD02E",
				shape = "Cylinder",
			},
			{ name = "CottonStand", center = { 118, 34 }, size = { 14, 12 }, height = 9, color = "FF79BD" },
			{ name = "FunHouseMaze", center = { 180, 62 }, size = { 64, 60 }, height = 12, color = "9AA0C0" },
			{
				name = "BumperFloor",
				center = { 150, 126 },
				size = { 76, 52 },
				height = 1,
				color = "FFD02E",
				friction = 0.1,
			},
			{ name = "FoodCourt", center = { 95, 112 }, size = { 36, 26 }, height = 4, color = "FFFFFF" },
			{
				name = "Backstage",
				center = { 190, 25 },
				size = { 44, 36 },
				height = 1,
				color = "FF2E93",
				team = "Infected",
			},
			{ name = "Booth1", center = { 60, 110 }, size = { 10, 8 }, height = 7, color = "FFFFFF" },
			{ name = "Booth2", center = { 100, 80 }, size = { 10, 8 }, height = 7, color = "FFFFFF" },
			{ name = "Booth3", center = { 140, 60 }, size = { 10, 8 }, height = 7, color = "FFFFFF" },
			{ name = "Booth4", center = { 120, 130 }, size = { 10, 8 }, height = 7, color = "FFFFFF" },
		},
		hazards = {
			{
				name = "CarouselSpin",
				kind = "Knockback",
				shape = "circle",
				center = { 72, 70 },
				radius = 22,
				knockback = 40,
				stagger = 1.5,
			},
			{
				name = "BumperSlip",
				kind = "LowFriction",
				shape = "box",
				center = { 150, 126 },
				size = { 76, 52 },
				friction = 0.1,
			},
			{
				name = "CottonGoo",
				kind = "Goo",
				shape = "box",
				center = { 118, 40 },
				size = { 50, 30 },
				infectionPerSec = 8,
			},
		},
		objectives = { { 78, 46 }, { 95, 112 }, { 180, 100 } },
		extraction = { 130, 148 }, -- pulled in from 152 so the 18-stud pad clears the south wall
	},
	{
		name = "Line 0 Subway",
		format = "blockout",
		localSize = { 220, 160 },
		accent = Brand.Color.HazardYellow,
		floorColor = Color3.fromRGB(26, 23, 48),
		wallColor = Color3.fromRGB(106, 99, 136),
		survivorSpawn = "EntranceHall",
		lighting = { -- underground: MOOD via cool-blue tint + fog, NOT darkness (kept bright)
			clockTime = 12,
			brightness = 2,
			ambient = Color3.fromRGB(88, 92, 115),
			outdoorAmbient = Color3.fromRGB(80, 86, 110),
			fogColor = Color3.fromRGB(60, 70, 110),
			fogStart = 90,
			fogEnd = 280,
			ccTint = Color3.fromRGB(200, 215, 255),
			ccSaturation = 0.04,
			ccBrightness = 0.03,
			ccContrast = 0.1,
		},
		parts = {
			{
				name = "EntranceHall",
				center = { 30, 28 },
				size = { 52, 44 },
				height = 1,
				color = "2EA8FF",
				team = "Survivor",
			},
			{
				name = "TunnelMouth",
				center = { 192, 138 },
				size = { 46, 40 },
				height = 1,
				color = "FF2E93",
				team = "Infected",
			},
			{ name = "NorthPlatform", center = { 110, 52 }, size = { 184, 28 }, height = 1, color = "8A8398" },
			{ name = "TrackBed", center = { 110, 82 }, size = { 200, 22 }, height = 0.5, color = "1A1730" },
			{ name = "SouthPlatform", center = { 110, 112 }, size = { 184, 28 }, height = 1, color = "8A8398" },
			{ name = "FloodedRoom", center = { 40, 135 }, size = { 50, 34 }, height = 1, color = "25D0FF" },
			{ name = "Turnstile1", center = { 44, 56 }, size = { 6, 4 }, height = 4, color = "FFFFFF" },
			{ name = "Turnstile2", center = { 50, 56 }, size = { 6, 4 }, height = 4, color = "FFFFFF" },
			{ name = "Turnstile3", center = { 56, 56 }, size = { 6, 4 }, height = 4, color = "FFFFFF" },
			{ name = "Pillar1", center = { 56, 50 }, size = { 8, 8 }, height = 14, color = "6A6388" },
			{ name = "Pillar2", center = { 136, 50 }, size = { 8, 8 }, height = 14, color = "6A6388" },
			{ name = "Pillar3", center = { 86, 110 }, size = { 8, 8 }, height = 14, color = "6A6388" },
			{ name = "Pillar4", center = { 146, 110 }, size = { 8, 8 }, height = 14, color = "6A6388" },
		},
		hazards = {
			{
				name = "TrainSweep",
				kind = "MovingHazard",
				carSize = { 50, 12, 14 },
				path = { from = { -30, 82 }, to = { 250, 82 } },
				periodSeconds = 14,
				telegraphSeconds = 3,
				knockback = 60,
				downed = true,
			},
			{
				name = "ThirdRail",
				kind = "Electrified",
				shape = "box",
				center = { 110, 70 },
				size = { 200, 2 },
				stun = 1.5,
				damage = 5,
				infectionPerSec = 6,
			},
			{
				name = "FloodedRoom",
				kind = "Slow",
				shape = "box",
				center = { 40, 135 },
				size = { 50, 34 },
				walkSpeedMult = 0.6,
				infectionPerSec = 4,
			},
		},
		objectives = { { 165, 50 }, { 70, 110 }, { 170, 110 } },
		extraction = { 196, 26 },
	},
}

return MapConfig
