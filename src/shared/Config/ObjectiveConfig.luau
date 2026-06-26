--[[
	ObjectiveConfig
	---------------
	Phase 5 — the Outbreak objective race. Survivors POWER a set of generators
	(hold a prompt), which ARMS the central extraction pad; then all living
	survivors hold the pad together to ESCAPE and win. Each generator powered
	fires a team-wide CLEANSE PULSE (the readable comeback). All tunable here.
]]

local ObjectiveConfig = {
	-- Generators the survivors must power. Per-map POSITIONS live in MapConfig; every
	-- map must define exactly GEN_COUNT generators.
	GEN_COUNT = 3,
	GEN_HOLD_SECONDS = 6, -- ProximityPrompt hold to power one generator (exposure window)
	GEN_RANGE = 10, -- prompt activation distance

	-- Extraction finale (the central pad, armed once all generators are powered).
	-- The pad's world position comes from MapConfig.EXTRACT_CENTER (per map).
	EXTRACT_RANGE = 12, -- horizontal studs from center counted as "on the pad"
	EXTRACT_ABANDON_RANGE = 75, -- survivors farther than this don't gate the hold (no lone-straggler lock)
	EXTRACT_HOLD_SECONDS = 8, -- continuous all-aboard seconds to escape (progress = 100/this per sec)
	EXTRACT_DECAY = 20, -- progress %/sec lost when not all-aboard (non-punishing, no instant reset)

	-- Anti-snowball: each generator completion cleanses the whole survivor team.
	CLEANSE_RELIEF = 35, -- infection % removed from each standing survivor
	CLEANSE_IMMUNITY = 3, -- seconds of immunity granted by a cleanse (reuses immuneUntil)

	REWARD_GENERATOR = 25, -- coins to the survivor who finishes a generator (cf. REWARD_RESCUE = 30)
}

return ObjectiveConfig
