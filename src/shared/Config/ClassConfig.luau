--[[
	ClassConfig
	-----------
	Outbreak Zero class definitions (from the design's class cards). MVP set:
	2 human (Assault, Medic) + 2 infected (Bruiser, Stalker). Engineer/Scout and
	Spitter/Controller are designed but not yet implemented.

	Each player keeps a chosen class PER FACTION (the class-select has a faction
	toggle); the round's assigned role decides which one applies. `stats {hp,spd,pwr}`
	are 0-1 bar values for the class-select UI; `walkSpeed` is the real in-game
	speed. `ability` is shown now and wired up in the abilities increment.
]]

local ClassConfig = {}

ClassConfig.DEFAULT_HUMAN = "Assault"
ClassConfig.DEFAULT_INFECTED = "Bruiser"

ClassConfig.classes = {
	Assault = {
		faction = "Human",
		display = "Assault",
		unlockCost = 0, -- starter class (free)
		blurb = "Front-line pressure. High damage & grenades.",
		ability = { name = "Frag Grenade", desc = "Lob a grenade that stuns infected in a blast." },
		walkSpeed = 16,
		stats = { hp = 0.6, spd = 0.5, pwr = 0.75 },
	},
	Medic = {
		faction = "Human",
		display = "Medic",
		unlockCost = 250, -- unlock with coins in the shop
		blurb = "Heal & cleanse. Purges infection and revives faster.",
		ability = { name = "Cleanse Beam", desc = "Drain infection from yourself and nearby allies." },
		walkSpeed = 16,
		stats = { hp = 0.55, spd = 0.5, pwr = 0.4 },
	},
	Bruiser = {
		faction = "Infected",
		display = "Bruiser",
		unlockCost = 0, -- starter class (free)
		blurb = "Breaks defenses. Huge HP, slow but devastating.",
		ability = { name = "Ground Slam", desc = "Slam the ground for a burst of infection nearby." },
		walkSpeed = 18,
		stats = { hp = 0.95, spd = 0.3, pwr = 0.8 },
	},
	Stalker = {
		faction = "Infected",
		display = "Stalker",
		unlockCost = 300, -- unlock with coins in the shop
		blurb = "Ambush & isolate. Fast, stealthy, picks off stragglers.",
		ability = { name = "Cloak Lunge", desc = "Briefly cloak and surge forward to ambush." },
		walkSpeed = 24,
		stats = { hp = 0.4, spd = 0.85, pwr = 0.55 },
	},
}

-- Display order per faction, for the class-select UI.
ClassConfig.humanOrder = { "Assault", "Medic" }
ClassConfig.infectedOrder = { "Bruiser", "Stalker" }

return ClassConfig
