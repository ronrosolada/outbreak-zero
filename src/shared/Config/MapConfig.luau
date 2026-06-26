--[[
	MapConfig
	---------
	Phase 6 — data-driven arena layouts. MapService rebuilds the arena from one of
	these per match (random rotation). Each map defines its own cover, generator,
	extraction, spawn, and hazard placement plus an accent color, so every map feels
	distinct while reusing one builder. Theme-neutral primitives; skinned later.

	All positions are arena-space (centered on 0,0,0). Generators must sit clear of
	cover and the center pad; hazards are circular floor zones that fill survivors'
	infection while they stand in them (see InfectionConfig.HAZARD_FILL_RATE).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

-- Per-map spawn points (placed by index, spread around the center). Each set is
-- kept clear of THAT map's cover blocks and hazard zones so no one spawns inside
-- a wall or a contamination patch.
local RING = { -- Grid Sector: diagonal ring (its cover/hazards avoid this band)
	Vector3.new(-20, 0, -20),
	Vector3.new(20, 0, -20),
	Vector3.new(-20, 0, 20),
	Vector3.new(20, 0, 20),
	Vector3.new(0, 0, -25),
	Vector3.new(0, 0, 25),
	Vector3.new(-25, 0, 0),
	Vector3.new(25, 0, 0),
}

local CARGO_SPAWNS = { -- Cargo Bay: central aisle (cover sits at z=+/-50; hazards avoided)
	Vector3.new(-30, 0, -12),
	Vector3.new(-12, 0, -12),
	Vector3.new(12, 0, -12),
	Vector3.new(30, 0, -12),
	Vector3.new(-30, 0, 12),
	Vector3.new(-12, 0, 12),
	Vector3.new(12, 0, 12),
	Vector3.new(30, 0, 12),
}

local BIO_SPAWNS = { -- Bio-Dome: on the axes, clear of the diagonal inner cover ring
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

MapConfig.maps = {
	{
		name = "Grid Sector",
		accent = Brand.Color.HumanBlue,
		floorColor = Brand.Color.BgDeep,
		coverColor = Brand.Color.Panel,
		cover = {
			Vector3.new(-50, 5, -40),
			Vector3.new(40, 5, -55),
			Vector3.new(-30, 5, 50),
			Vector3.new(60, 5, 30),
			Vector3.new(-70, 5, 60),
			Vector3.new(70, 5, -20),
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
		accent = Brand.Color.HazardYellow,
		floorColor = Brand.Color.BgDeep,
		coverColor = Brand.Color.Panel,
		cover = { -- two rows of "containers"
			Vector3.new(-40, 5, -50),
			Vector3.new(0, 5, -50),
			Vector3.new(40, 5, -50),
			Vector3.new(-40, 5, 50),
			Vector3.new(0, 5, 50),
			Vector3.new(40, 5, 50),
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
		accent = Brand.Color.SafeGreen,
		floorColor = Brand.Color.BgDeep,
		coverColor = Brand.Color.Panel,
		cover = { -- clustered inner ring + side blocks
			Vector3.new(-26, 5, -26),
			Vector3.new(26, 5, 26),
			Vector3.new(-26, 5, 26),
			Vector3.new(26, 5, -26),
			Vector3.new(-62, 5, 0),
			Vector3.new(62, 5, 0),
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
