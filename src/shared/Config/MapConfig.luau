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
		lighting = { -- cool blue powered-down server hall
			clockTime = 0,
			brightness = 1.2,
			ambient = Color3.fromRGB(30, 34, 52),
			outdoorAmbient = Color3.fromRGB(18, 22, 40),
			fogColor = Brand.Color.BgDeep,
			fogStart = 70,
			fogEnd = 200,
			ccTint = Color3.fromRGB(190, 215, 255),
			ccSaturation = 0.06,
			ccBrightness = 0,
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
		decals = {
			{ pos = Vector3.new(-72, 18.5, 15), size = Vector3.new(16, 0.5, 16), color = "accent" },
			{ pos = Vector3.new(72, 18.5, -15), size = Vector3.new(16, 0.5, 16), color = "accent" },
			{ pos = Vector3.new(-50, 11, -40), size = Vector3.new(3, 3, 3), shape = "orb", color = "accent" },
			{ pos = Vector3.new(60, 11, 30), size = Vector3.new(3, 3, 3), shape = "orb", color = "accent" },
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
		lighting = { -- warm amber loading dock at dusk
			clockTime = 17.5,
			brightness = 1.1,
			ambient = Color3.fromRGB(40, 34, 24),
			outdoorAmbient = Color3.fromRGB(28, 24, 16),
			fogColor = Color3.fromRGB(44, 33, 18),
			fogStart = 80,
			fogEnd = 210,
			ccTint = Color3.fromRGB(255, 238, 200),
			ccSaturation = 0.05,
			ccBrightness = 0,
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
		decals = {
			{ pos = Vector3.new(-70, 12.5, -58), size = Vector3.new(20, 0.5, 10), color = "accent" },
			{ pos = Vector3.new(70, 12.5, -58), size = Vector3.new(20, 0.5, 10), color = "accent" },
			{ pos = Vector3.new(-44, 12.5, 58), size = Vector3.new(20, 0.5, 10), color = "accent" },
			{ pos = Vector3.new(44, 12.5, 58), size = Vector3.new(20, 0.5, 10), color = "accent" },
			{ pos = Vector3.new(-70, 14, -58), size = Vector3.new(2.5, 2.5, 2.5), shape = "orb", color = "accent" },
			{ pos = Vector3.new(70, 14, -58), size = Vector3.new(2.5, 2.5, 2.5), shape = "orb", color = "accent" },
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
		lighting = { -- humid green greenhouse
			clockTime = 11,
			brightness = 1.15,
			ambient = Color3.fromRGB(26, 40, 30),
			outdoorAmbient = Color3.fromRGB(20, 34, 26),
			fogColor = Color3.fromRGB(30, 62, 46),
			fogStart = 45,
			fogEnd = 160,
			ccTint = Color3.fromRGB(205, 255, 220),
			ccSaturation = 0.14,
			ccBrightness = 0,
			ccContrast = 0,
			atmosphere = { density = 0.30, haze = 1.5, color = Color3.fromRGB(200, 230, 210) },
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
		decals = {
			{ pos = Vector3.new(-58, 9, 48), size = Vector3.new(3, 3, 3), shape = "orb", color = "accent" },
			{ pos = Vector3.new(60, 9, 18), size = Vector3.new(3, 3, 3), shape = "orb", color = "accent" },
			{ pos = Vector3.new(-66, 11, -8), size = Vector3.new(2.5, 2.5, 2.5), shape = "orb", color = "accent" },
			{ pos = Vector3.new(-66, 10.5, -8), size = Vector3.new(14, 0.5, 14), color = "accent" },
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
}

return MapConfig
