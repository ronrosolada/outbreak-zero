--[[
	InfectionConfig
	---------------
	Tunables for the infection meter + downed-and-rescue system. All values are
	balanced for fast Roblox matches; tweak freely (live-syncs on re-Play).
]]

local InfectionConfig = {
	-- == Contact infection (the "bite": being near an infected fills your meter) ==
	TICK = 0.2, -- server update interval (seconds)
	CONTACT_RANGE = 7, -- studs: an infected within this range fills your meter
	FILL_RATE = 22, -- infection % gained per second of contact (~4.5s to down)
	DECAY_RATE = 14, -- infection % lost per second once out of contact
	DECAY_DELAY = 2, -- seconds out of contact before decay begins
	SPAWN_IMMUNITY = 5, -- seconds a fresh/revived survivor can't gain infection
	HAZARD_FILL_RATE = 14, -- infection %/sec while standing in a map contamination zone (Phase 6)

	-- == Downed & rescue ==
	BLEED_OUT_SECONDS = 25, -- time downed before converting to infected
	RESCUE_SECONDS = 4, -- hold time to revive a downed ally
	RESCUE_RANGE = 8, -- studs: how close you must be to start a rescue
	SECURE_RANGE = 14, -- studs: an infected this close to a downed ally BLOCKS rescue
	RESCUE_INFECTION = 40, -- infection % a revived survivor starts at (repeat downs hurt)

	-- == Class / ability infection levers (design handoff) ==
	GOO_POOL_FILL_RATE = 8, -- %/sec while standing in a Spitter goo pool
	NEST_SLOW_MULT = 0.6, -- survivor WalkSpeed multiplier inside a Controller nest
	NEST_FILL_BONUS = 12, -- extra infection %/sec inside a Controller nest
	MEDIC_AURA_RANGE = 22, -- studs: survivors within this of a Medic decay infection faster (AllyDecayMult)
	-- NOTE: Patient Zero range/buff-duration live in ClassConfig.PatientZero (InfectRangeMult /
	-- BuffDuration) — the single source of truth the code reads. Do not re-add PZ tunables here.
}

return InfectionConfig
